function Export-WingetHtmlReport {
    <#
    .SYNOPSIS
        Exports an array of objects to a highly styled, interactive HTML report.

    .DESCRIPTION
        Takes an array of objects, prompts the user for a save location, and generates
        a premium dark-mode HTML file containing all the data with sortable columns
        and a live search filter. Automatically opens the file in the default browser.

    .PARAMETER Data
        The array of custom objects to export.

    .PARAMETER ReportTitle
        The title to display at the top of the report.

    .PARAMETER ReportType
        A short string used for the generated filename (e.g., 'NewPackages').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Data,

        [Parameter(Mandatory=$true)]
        [string]$ReportTitle,

        [Parameter(Mandatory=$true)]
        [string]$OutFile
    )

    if (-not $Data -or $Data.Count -eq 0) {
        Write-Warning "No data available to export to HTML."
        return
    }

    # Prompt user for save location
    Write-Host ""
    Write-Host "HTML Export requested." -ForegroundColor Cyan
    $defaultPath = [System.Environment]::GetFolderPath('UserProfile') + "\Downloads"
    $savePath = Read-Host "Enter folder path to save the HTML report (Press Enter for '$defaultPath')"
    
    if ([string]::IsNullOrWhiteSpace($savePath)) {
        $savePath = $defaultPath
    }

    # Ensure directory exists
    if (-not (Test-Path $savePath)) {
        try {
            New-Item -ItemType Directory -Path $savePath -Force | Out-Null
        }
        catch {
            Write-Warning "Could not create directory '$savePath'. Saving to current directory instead."
            $savePath = $PWD.Path
        }
    }

    # Generate filename
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $filename = "WinBatch_${ReportType}_${timestamp}.html"
    $fullPath = Join-Path $savePath $filename

    Write-Host "Generating HTML report..." -ForegroundColor DarkGray

    # Extract column names from the first object
    $firstItem = $Data[0]
    $properties = if ($firstItem -is [PSCustomObject]) {
        $firstItem.PSObject.Properties.Name
    } elseif ($firstItem -is [Hashtable]) {
        $firstItem.Keys | Sort-Object
    } else {
        $firstItem | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
    }

    # Build Table Headers
    $thHtml = ""
    foreach ($prop in $properties) {
        $thHtml += "<th>$prop</th>`n"
    }

    # Build Table Rows
    $trHtml = ""
    foreach ($item in $Data) {
        $trHtml += "<tr>`n"
        foreach ($prop in $properties) {
            $val = if ($item -is [Hashtable]) { $item[$prop] } else { $item.$prop }
            # Escape HTML
            $escapedVal = [System.Net.WebUtility]::HtmlEncode([string]$val)
            $trHtml += "<td>$escapedVal</td>`n"
        }
        $trHtml += "</tr>`n"
    }

    # HTML Template
    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$ReportTitle - WingetBatch</title>
    <style>
        :root {
            --bg-base: #09090b;
            --bg-card: rgba(24, 24, 27, 0.6);
            --border: rgba(255, 255, 255, 0.1);
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --accent: #10b981;
            --accent-hover: #059669;
        }
        body {
            background-color: var(--bg-base);
            color: var(--text-main);
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            margin: 0;
            padding: 2rem;
            min-height: 100vh;
            background-image: 
                radial-gradient(circle at 15% 50%, rgba(16, 185, 129, 0.05), transparent 25%),
                radial-gradient(circle at 85% 30%, rgba(56, 189, 248, 0.05), transparent 25%);
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        header {
            display: flex;
            justify-content: space-between;
            align-items: flex-end;
            margin-bottom: 2rem;
            border-bottom: 1px solid var(--border);
            padding-bottom: 1rem;
        }
        h1 {
            margin: 0;
            font-size: 2.5rem;
            font-weight: 700;
            letter-spacing: -0.025em;
            background: linear-gradient(to right, #fff, #94a3b8);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .meta {
            color: var(--text-muted);
            font-size: 0.875rem;
        }
        .controls {
            margin-bottom: 1.5rem;
            display: flex;
            gap: 1rem;
        }
        input[type="text"] {
            flex-grow: 1;
            background: rgba(0,0,0,0.3);
            border: 1px solid var(--border);
            color: var(--text-main);
            padding: 0.75rem 1rem;
            border-radius: 0.5rem;
            font-size: 1rem;
            outline: none;
            transition: border-color 0.2s, box-shadow 0.2s;
        }
        input[type="text"]:focus {
            border-color: var(--accent);
            box-shadow: 0 0 0 1px var(--accent);
        }
        .table-container {
            background: var(--bg-card);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid var(--border);
            border-radius: 1rem;
            overflow: auto;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
        }
        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
        }
        th {
            background: rgba(255,255,255,0.02);
            color: var(--text-muted);
            font-weight: 600;
            font-size: 0.875rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            padding: 1rem;
            border-bottom: 1px solid var(--border);
            cursor: pointer;
            user-select: none;
            transition: background 0.2s;
        }
        th:hover {
            background: rgba(255,255,255,0.05);
            color: var(--text-main);
        }
        td {
            padding: 1rem;
            border-bottom: 1px solid rgba(255,255,255,0.05);
            font-size: 0.95rem;
            word-break: break-word;
        }
        tr:last-child td {
            border-bottom: none;
        }
        tr:hover td {
            background: rgba(255,255,255,0.02);
        }
        /* Sort indicators */
        th::after {
            content: '';
            display: inline-block;
            margin-left: 0.5rem;
            opacity: 0.3;
        }
        th.asc::after { content: '▲'; opacity: 1; color: var(--accent); }
        th.desc::after { content: '▼'; opacity: 1; color: var(--accent); }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div>
                <h1>$ReportTitle</h1>
                <div class="meta">Generated by WingetBatch • $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))</div>
            </div>
            <div class="meta">$($Data.Count) records found</div>
        </header>

        <div class="controls">
            <input type="text" id="searchInput" placeholder="Search across all fields..." onkeyup="filterTable()">
        </div>

        <div class="table-container">
            <table id="dataTable">
                <thead>
                    <tr>
                        $thHtml
                    </tr>
                </thead>
                <tbody>
                    $trHtml
                </tbody>
            </table>
        </div>
    </div>

    <script>
        // Client-side search filtering
        function filterTable() {
            const input = document.getElementById("searchInput");
            const filter = input.value.toLowerCase();
            const table = document.getElementById("dataTable");
            const tr = table.getElementsByTagName("tr");

            for (let i = 1; i < tr.length; i++) {
                let textValue = tr[i].textContent || tr[i].innerText;
                if (textValue.toLowerCase().indexOf(filter) > -1) {
                    tr[i].style.display = "";
                } else {
                    tr[i].style.display = "none";
                }
            }
        }

        // Client-side column sorting
        const getCellValue = (tr, idx) => tr.children[idx].innerText || tr.children[idx].textContent;
        const comparer = (idx, asc) => (a, b) => ((v1, v2) => 
            v1 !== '' && v2 !== '' && !isNaN(v1) && !isNaN(v2) ? v1 - v2 : v1.toString().localeCompare(v2)
            )(getCellValue(asc ? a : b, idx), getCellValue(asc ? b : a, idx));

        document.querySelectorAll('th').forEach(th => th.addEventListener('click', (() => {
            const table = th.closest('table');
            const tbody = table.querySelector('tbody');
            const asc = th.classList.contains('asc');
            
            // Remove sort classes from all headers
            table.querySelectorAll('th').forEach(el => {
                el.classList.remove('asc', 'desc');
            });
            
            // Add new sort class
            th.classList.add(asc ? 'desc' : 'asc');
            
            Array.from(tbody.querySelectorAll('tr'))
                .sort(comparer(Array.from(th.parentNode.children).indexOf(th), !asc))
                .forEach(tr => tbody.appendChild(tr));
        })));
    </script>
</body>
</html>
"@

    try {
        [System.IO.File]::WriteAllText($fullPath, $htmlContent, [System.Text.Encoding]::UTF8)
                            Write-Host "  - " -ForegroundColor Green -NoNewline
        Write-Host $fullPath -ForegroundColor White
        
        Write-Host "Opening report in default browser..." -ForegroundColor DarkGray
        Invoke-Item $fullPath
    }
    catch {
        Write-Error "Failed to save HTML report: $_"
    }
}



