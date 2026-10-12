import os
import sys

def convert_miseq_to_bclconvert(input_file, output_file, adapter1=None, adapter2=None):
    if not os.path.exists(input_file):
        print(f"Fehler: Datei '{input_file}' existiert nicht.")
        sys.exit(1)

    # Standardmäßig Nextera-Adapter (häufiger bei MiSeq). 
    # Falls Sie TruSeq nutzen, ändern Sie diese zu:
    # A1 = "AGATCGGAAGAGCACACGTCTGAACTCCAGTCA"
    # A2 = "AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT"
    if not adapter1:
        adapter1 = "CTGTCTCTTATACACATCT"
    if not adapter2:
        adapter2 = "CTGTCTCTTATACACATCT"

    # Offiziell erlaubte Spaltennamen in [BCLConvert_Data]
    VALID_BCLCONVERT_COLUMNS = {
        'Lane', 'Sample_ID', 'index', 'index2', 'Sample_Project', 'Sample_Name',
        'OverrideCycles', 'BarcodeMismatchesIndex1', 'BarcodeMismatchesIndex2',
        'AdapterRead1', 'AdapterRead2', 'AdapterBehavior', 'AdapterStringency'
    }

    sections = {}
    current_section = None
    
    # 1. Parsen des alten Samplesheets
    with open(input_file, 'r', encoding='utf-8') as f:
        for line in f:
            line_str = line.strip()
            if not line_str:
                continue
            
            # Identifiziere Sektionen wie [Header], [Reads], [Data]
            if line_str.startswith('[') and line_str.endswith(']'):
                current_section = line_str[1:-1].strip()
                sections[current_section] = []
            elif current_section:
                sections[current_section].append(line_str)

    # 2. Generieren des neuen BCL Convert v2 Formats
    with open(output_file, 'w', encoding='utf-8') as out:
        # Header-Bereich schreiben und v2 Kennzeichnung erzwingen
        out.write("[Header]\n")
        out.write("FileFormatVersion,2\n")
        out.write("IndexOrientation,Forward\n")
        
        if 'Header' in sections:
            for line in sections['Header']:
                if not any(k in line for k in ["IEMFileVersion", "FileFormatVersion"]):
                    out.write(f"{line}\n")
        out.write("\n")
            
        # Reads-Bereich konvertieren
        if 'Reads' in sections and len(sections['Reads']) > 0:
            out.write("[Reads]\n")
            read_count = 1
            for line in sections['Reads']:
                if ',' in line:
                    out.write(f"{line}\n")
                else:
                    clean_val = line.replace(',', '').strip()
                    if clean_val.isdigit():
                        out.write(f"Read{read_count}Cycles,{clean_val}\n")
                        read_count += 1
            out.write("\n")

        # BCLConvert Settings mit Adapter-Trimming-Konfiguration hinzufügen
        out.write("[BCLConvert_Settings]\n")
        out.write("FastqCompressionFormat,gzip\n")
        out.write(f"AdapterRead1,{adapter1}\n") 
        out.write(f"AdapterRead2,{adapter2}\n") 
        out.write("AdapterBehavior,trim\n")     
        out.write("\n")

        # Data-Sektion konvertieren und filtern
        if 'Data' in sections and len(sections['Data']) > 0:
            out.write("[BCLConvert_Data]\n")
            
            # KORREKTUR: Explizit das erste Element ([0]) der Liste abgreifen
            header_line = sections['Data'][0]
            old_headers = [h.strip() for h in header_line.split(',')]
            
            # Vorab-Mapping für Sample_ID korrigieren falls nötig
            temp_headers = []
            for h in old_headers:
                if h == 'Sample_Name' and 'Sample_ID' not in old_headers:
                    temp_headers.append('Sample_ID')
                else:
                    temp_headers.append(h)
            
            # Bestimmen, welche Spalten-Indizes wir behalten dürfen
            valid_indices = []
            new_headers = []
            
            # Falls 'Lane' komplett fehlt, merken wir uns das fürs spätere Einfügen
            add_lane_column = 'Lane' not in temp_headers
            if not add_lane_column:
                lane_idx = temp_headers.index('Lane')
                valid_indices.append(lane_idx)
                new_headers.append('Lane')
            else:
                new_headers.append('Lane')

            # Filtere alle restlichen Spalten anhand der White-List
            for idx, h in enumerate(temp_headers):
                if h == 'Lane':
                    continue
                if h in VALID_BCLCONVERT_COLUMNS:
                    valid_indices.append(idx)
                    new_headers.append(h)
                    
            # Schreibe die bereinigte Header-Zeile
            out.write(",".join(new_headers) + "\n")

            # Datenzeilen schreiben
            for row in sections['Data'][1:]:
                columns = [c.strip() for c in row.split(',')]
                if not any(columns):
                    continue
                
                while len(columns) < len(old_headers):
                    columns.append('')
                    
                new_columns = []
                if add_lane_column:
                    new_columns.append('1') 
                    
                for idx in valid_indices:
                    new_columns.append(columns[idx])
                    
                out.write(",".join(new_columns) + "\n")
                
    print(f"Erfolgreich konvertiert! Datei geschrieben nach: '{output_file}'")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Nutzung: python convert_sheet.py <input_miseq.csv> <output_bclconvert.csv> [optional: adapter1] [optional: adapter2]")
        sys.exit(1)
        
    # KORREKTUR: Fehlerfreie Zuweisung der CLI-Argumente
    a1 = sys.argv[3] if len(sys.argv) > 3 else None
    a2 = sys.argv[4] if len(sys.argv) > 4 else None
        
    convert_miseq_to_bclconvert(sys.argv[1], sys.argv[2], adapter1=a1, adapter2=a2)
