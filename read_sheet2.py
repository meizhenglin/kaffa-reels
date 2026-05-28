import subprocess
import sys

# Try to read Excel file
try:
    import pandas as pd
    
    # Read all sheets
    xlsx = pd.ExcelFile(r'C:\Users\admin\Desktop\新建 XLS 工作表.xlsx')
    print("Available sheets:", xlsx.sheet_names)
    
    # Read Sheet2 (index 1)
    if len(xlsx.sheet_names) > 1:
        df2 = pd.read_excel(xlsx, sheet_name=1)
        print("\n=== Sheet2 (Video URLs) ===")
        print("Columns:", list(df2.columns))
        print("Shape:", df2.shape)
        print("\nFirst 10 rows:")
        print(df2.head(10).to_string())
        print("\n\nAll rows:")
        print(df2.to_string())
except Exception as e:
    print(f"Error: {e}")
