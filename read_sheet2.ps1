# Read Sheet2 from Excel file
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $workbook = $excel.Workbooks.Open("C:\Users\admin\Desktop\新建 XLS 工作表.xlsx")
    
    Write-Host "Available sheets:"
    $workbook.Sheets | ForEach-Object { Write-Host "  - $($_.Name)" }
    
    # Get Sheet2
    if ($workbook.Sheets.Count -gt 1) {
        $sheet2 = $workbook.Sheets.Item(2)
        Write-Host "`n=== Sheet2 Content ==="
        
        $usedRange = $sheet2.UsedRange
        $rowCount = $usedRange.Rows.Count
        $colCount = $usedRange.Columns.Count
        
        Write-Host "Rows: $rowCount, Columns: $colCount"
        
        # Print header
        $header = @()
        for ($col = 1; $col -le $colCount; $col++) {
            $header += $sheet2.Cells.Item(1, $col).Text
        }
        Write-Host "Header: $($header -join ', ')"
        
        # Print first 20 rows
        $maxRows = [Math]::Min($rowCount, 20)
        for ($row = 2; $row -le $maxRows; $row++) {
            $rowData = @()
            for ($col = 1; $col -le $colCount; $col++) {
                $rowData += $sheet2.Cells.Item($row, $col).Text
            }
            Write-Host "Row $row`: $($rowData -join '|')"
        }
        
        # Print all rows to a temp file
        $output = @()
        $output += "Title,Smooth,Standard,HD"
        for ($row = 2; $row -le $rowCount; $row++) {
            $rowData = @()
            for ($col = 1; $col -le $colCount; $col++) {
                $cell = $sheet2.Cells.Item($row, $col).Text
                $cell = $cell -replace ',', '，'
                $rowData += $cell
            }
            $output += ($rowData -join ',')
        }
        
        $output | Out-File -FilePath "C:\Users\admin\arab_drama_app\sheet2_data.csv" -Encoding UTF8
        Write-Host "`nData saved to: C:\Users\admin\arab_drama_app\sheet2_data.csv"
    }
    
    $workbook.Close($false)
}
catch {
    Write-Host "Error: $_"
}
finally {
    $excel.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
}
