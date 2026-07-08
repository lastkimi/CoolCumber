import os
import re

directory = '/Users/brucelieu/Desktop/MacThermFlow/ThermFlowApp/Sources'

replacements = [
    (r'Color\.white\.opacity\(0\.05\)', 'Color(white: 0.163)'),
    (r'Color\.white\.opacity\(0\.1\)', 'Color(white: 1.0, opacity: 0.08)'),
    (r'Color\.white\.opacity\(0\.03\)', 'Color(white: 0.140)'),
    (r'Color\.white\.opacity\(0\.08\)', 'Color(white: 0.200)')
]

for root, _, files in os.walk(directory):
    for file in files:
        if file.endswith('.swift') and file not in ['DashboardView.swift', 'CoolingView.swift', 'SmartBarView.swift']:
            path = os.path.join(root, file)
            with open(path, 'r') as f:
                content = f.read()
            
            new_content = content
            for old, new in replacements:
                new_content = re.sub(old, new, new_content)
            
            if new_content != content:
                with open(path, 'w') as f:
                    f.write(new_content)
                print(f"Updated {file}")

