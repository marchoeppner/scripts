#!/usr/bin/env python3

import csv

def process_tsv_file(input_file, output_file):
    """
    Process TSV file and add 'best_translation' column based on 'status' column.
    
    If status is NO_GBIF_DE, use qwen_german column value
    If status is DIFF, use gbif_german column value
    """
    
    with open(input_file, 'r', newline='', encoding='utf-8') as infile, \
         open(output_file, 'w', newline='', encoding='utf-8') as outfile:
        
        # Read the input file
        reader = csv.DictReader(infile, delimiter='\t')
        
        # Get fieldnames from the header
        fieldnames = reader.fieldnames
        
        # Add new column name to fieldnames
        fieldnames.append('best_translation')
        
        # Create writer with updated fieldnames
        writer = csv.DictWriter(outfile, fieldnames=fieldnames, delimiter='\t')
        
        # Write header
        writer.writeheader()
        
        # Process each row
        for row in reader:
            status = row['status']
            
            if status == 'NO_GBIF_DE':
                best_translation = row['qwen_german']
            elif status == 'DIFF':
                best_translation = row['gbif_german']
            elif status == 'MATCH':
                best_translation = row['qwen_german']
            else:
                # For other statuses or empty values, leave blank
                best_translation = ''
            
            # Add the new column value
            row['best_translation'] = best_translation
            
            # Write the updated row
            writer.writerow(row)

if __name__ == "__main__":
    input_file = '/work_syn/ngs/foodme/name_lookup/verified_common_names_de.tsv'
    output_file = '/work_syn/ngs/foodme/name_lookup/verified_common_names_de_with_best_translation.tsv'
    
    process_tsv_file(input_file, output_file)
    print(f"Processed file saved to {output_file}")
