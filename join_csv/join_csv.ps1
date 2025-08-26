param(
    [Parameter(Mandatory=$true)] [string]$ParentCsvPath,
    [Parameter(Mandatory=$true)] [string]$ChildCsvDir,
    [Parameter(Mandatory=$true)] [string]$OutputDir,
    [string]$EncodingName = 'shift_jis',   # 'shift_jis' or 'utf-8'
    [string]$Delimiter    = ','            # 区切り（通常は ,）
)

$ErrorActionPreference = 'Stop'

function Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Die ($m){ throw $m }

if (!(Test-Path $ParentCsvPath)) { Die "親CSVが見つかりません: $ParentCsvPath" }
if (!(Test-Path $ChildCsvDir))   { Die "子CSVフォルダが見つかりません: $ChildCsvDir" }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Add-Type -AssemblyName 'Microsoft.VisualBasic'

function Get-Encoding([string]$name){
    if ($name -eq 'shift_jis') { return [System.Text.Encoding]::GetEncoding(932) }
    return [System.Text.Encoding]::GetEncoding($name)
}

function Read-CsvSafe {
    param([string]$Path,[string]$Delim,[string]$Encoding)
    $enc = Get-Encoding $Encoding
    $sr  = New-Object System.IO.StreamReader($Path, $enc)
    $p   = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($sr)
    $p.HasFieldsEnclosedInQuotes = $true
    $p.SetDelimiters($Delim)

    $headers = $p.ReadFields()
    if (-not $headers) { throw "ヘッダー行が読み取れません: $Path" }

    $rows = New-Object System.Collections.Generic.List[object]
    while (-not $p.EndOfData) {
        $fields = $p.ReadFields()
        $map = [ordered]@{}
        for ($i=0; $i -lt $headers.Length; $i++) {
            $map[$headers[$i]] = if ($i -lt $fields.Length) { $fields[$i] } else { '' }
        }
        $rows.Add($map)
    }
    $p.Close(); $sr.Close()
    return @{ Headers = $headers; Rows = $rows }
}

function Escape-Csv([string]$s, [string]$Delim) {
    if ($null -eq $s) { return '' }
    $needQuote = $s.Contains($Delim) -or $s.Contains("`n") -or $s.Contains("`r") -or $s.Contains('"') -or $s -match '^\s|\s$'
    $s2 = $s -replace '"','""'
    if ($needQuote) { return '"' + $s2 + '"' } else { return $s2 }
}

function Write-CsvSafe {
    param(
        $Headers,    # 型縛りを緩和
        $RowMaps,    # （OrderedDictionary対応）
        [string]$Path,[string]$Delim,[string]$Encoding
    )
    $enc = Get-Encoding $Encoding
    $sw  = New-Object System.IO.StreamWriter($Path, $false, $enc)
    $sw.WriteLine( ($Headers | ForEach-Object { Escape-Csv $_ $Delim }) -join $Delim )
    foreach ($row in $RowMaps) {
        $vals = foreach ($h in $Headers) {
            if ($row.Contains($h)) { Escape-Csv ([string]$row[$h]) $Delim } else { '' }
        }
        $sw.WriteLine( $vals -join $Delim )
    }
    $sw.Close()
}

# 親CSVの読み込み & IDインデックス化
Info "親CSV読込: $ParentCsvPath"
$parent = Read-CsvSafe -Path $ParentCsvPath -Delim $Delimiter -Encoding $EncodingName
$parentHeaders = New-Object System.Collections.Generic.List[string]; $parentHeaders.AddRange($parent.Headers)
if (-not ($parentHeaders -contains 'ID')) { Die "親CSVに 'ID' 列がありません。" }

$parentRows = $parent.Rows
$index = @{}  # Hashtable（ContainsKey 使用OK）
foreach ($r in $parentRows) {
    $id = [string]$r['ID']
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $index[$id] = $r
}

# 出力ヘッダー（親列から開始）
$outputHeaders = New-Object System.Collections.Generic.List[string]
$outputHeaders.AddRange($parentHeaders)

# 子CSVを順次マージ（FIRST優先）
$childFiles = Get-ChildItem -Path $ChildCsvDir -Filter *.csv -File | Sort-Object Name
if ($childFiles.Count -eq 0){ Warn "子CSVが見つかりません。" }

$childNo = 0
foreach ($cf in $childFiles) {
    $childNo++
    $alias = "c$childNo_"

    Info "子CSV読込＆マージ: $($cf.FullName)"
    $child = Read-CsvSafe -Path $cf.FullName -Delim $Delimiter -Encoding $EncodingName

    if (-not ($child.Headers -contains '旧URL')) { Warn "スキップ（'旧URL' 列なし）: $($cf.Name)"; continue }

    $childDataCols = @($child.Headers | Where-Object { $_ -ne '旧URL' })

    foreach ($c in $childDataCols) {
        $aliasCol = $alias + $c
        if (-not $outputHeaders.Contains($aliasCol)) { [void]$outputHeaders.Add($aliasCol) }
    }

    foreach ($row in $child.Rows) {
        $oldUrl = [string]$row['旧URL']
        if ([string]::IsNullOrWhiteSpace($oldUrl)) { continue }

        $pos = $oldUrl.LastIndexOf('_')
        if ($pos -lt 0) { continue }

        $parentId = $oldUrl.Substring($pos + 1)
        if (-not $index.ContainsKey($parentId)) { continue }

        $target = $index[$parentId]
        foreach ($c in $childDataCols) {
            $val = [string]$row[$c]
            if ([string]::IsNullOrWhiteSpace($val)) { continue }

            $aliasCol = $alias + $c
            # ここを .Contains に修正
            if ($target.Contains($aliasCol)) {
                if ([string]::IsNullOrWhiteSpace([string]$target[$aliasCol])) { $target[$aliasCol] = $val }
            } else {
                $target[$aliasCol] = $val
            }
        }
    }
}

# 出力
$outPath = Join-Path $OutputDir 'merged.csv'
Info "CSV出力: $outPath"
Write-CsvSafe -Headers $outputHeaders -RowMaps $parentRows -Path $outPath -Delim $Delimiter -Encoding $EncodingName

Info "完了。親行数: $($parentRows.Count) / 子ファイル数: $($childFiles.Count)"
