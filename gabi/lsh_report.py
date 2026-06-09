#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import json
from reportlab.lib.enums import TA_JUSTIFY, TA_RIGHT
from reportlab.lib.units import cm
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.graphics.shapes import Drawing, Line
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Image, Table, PageBreak
from reportlab.lib import colors

from datetime import date


def get_status(key, reference):

    qc_pass = reference["pass"]
    if key in qc_pass:
        return "pass"
    qc_fail = reference["fail"]
    if key in qc_fail:
        return "fail"
    qc_warn = reference["warn"]
    if key in qc_warn:
        return "warn"
    qc_missing = reference["missing"]
    if key in qc_missing:
        return "missing"

    return "missing"


def get_serotype(serotypes):

    result = {"serotype": "", "pathotype": None, "genes": None, "classification": None, "tool": None}

    for tool, data in serotypes.items():

        if (tool == "sccmec"):
            result["tool"] = tool
            result["serotype"] = data["type"]
            if (data["mecA"] == "+"):
                result["genes"] = "mecA"
        elif (tool == "ectyper"):
            result["tool"] = tool
            result["serotype"] = data["Serotype"]
            result["genes"] = data["PathotypeGenes"]
            if "ND" not in data["Pathotype"]:
                result["pathotype"] = data["Pathotype"]
            result["classification"] = data["StxSubtypes"]
        elif (tool == "sistr"):
            result["tool"] = tool
            result["serotype"] = data["serogroup"]
            result["pathotype"] = data["serovar"]
        elif (tool == "kaptive"):
            result["tool"] = tool
            result["serotype"] = data["best_match"]
        elif (tool == "lissero"):
            result["tool"] = tool
            result["serotype"] = data["SEROTYPE"]
        elif (tool == "btyper3"):
            result["tool"] = tool
            result["serotype"] = data["Adjusted_panC_Group(predicted_species)"]
            result["gene"] = data["Bt(genes)"]

    return result


today = date.today()
date = today.strftime("%d.%m.%Y")

# Command line arguments
parser = argparse.ArgumentParser(description="Script options")
parser.add_argument("--json")
parser.add_argument("--logo", required=True)
parser.add_argument("--output")
args = parser.parse_args()

# Use defaults or take from command line
outfile = args.output if args.output else args.json.split("/")[-1].replace(".qc.json", ".pdf")

content = []

pdf = SimpleDocTemplate(outfile, pagesize=A4,
                        rightMargin=35, leftMargin=35,
                        topMargin=20, bottomMargin=20)

# Define styles
styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name='Justify', alignment=TA_JUSTIFY))
styles.add(ParagraphStyle(name='H1', fontSize=14))
styles.add(ParagraphStyle(name='H2', fontSize=12))

styles.add(ParagraphStyle(name='header', fontSize=8))


styles.add(ParagraphStyle(name='H2_bg', backColor="#CCCCCC", borderPadding=4, fontSize=12))
styles.add(ParagraphStyle(name='Standard', fontSize=10))
styles.add(ParagraphStyle(name='table', fontSize=8))
styles.add(ParagraphStyle(name='Taxon', fontSize=10, fontName="Helvetica"))


styles.add(ParagraphStyle(name='Gray', fontSize=10, textColor="#9c9c9c"))

styles.add(ParagraphStyle(name='Bold', fontSize=10, fontName="Helvetica-Bold"))
styles.add(ParagraphStyle(name='H2_right', fontSize=12, alignment=TA_RIGHT))
styles.add(ParagraphStyle(name='Info', fontSize=8))
styles.add(ParagraphStyle(name='Sequence', fontSize=8, fontName="Courier"))

styles.add(ParagraphStyle(name='Status_pass', backColor="#72CC77", fontSize=10))
styles.add(ParagraphStyle(name='Status_fail', backColor="#D46860", fontSize=10))
styles.add(ParagraphStyle(name='Status_warn', backColor="#CECB43", fontSize=10))
styles.add(ParagraphStyle(name='Status_missing', fontSize=10))

styles.add(ParagraphStyle(name='Unicode', fontName="D050000L", fontSize=10))

status_styles = {
    "pass": styles["Status_pass"],
    "fail": styles["Status_fail"],
    "warn": styles["Status_warn"],
    "missing": styles["Status_missing"],
}

qc_lookups = {
    "Total length": "quast_assembly",
    "# contigs": "quast_contigs",
    "N50": "quast_n50",
    "GC (%)": "quast_gc",
    "Duplication ratio": "quast_duplication"
}

# The header
logo = Image(args.logo, height=3 * cm, width=6 * cm)
logo.hAlign = "RIGHT"
content.append(logo)
content.append(Spacer(1, 20))

has_illumina = False
has_nanopore = False

##############################
# Parse JSON
##############################
# Parse JSON file to extract relevant information
with open(args.json) as json_file:
    data = json.load(json_file)

sample = data["sample"]
run_date = data["date"]
qc = data["qc"]
settings = data["pipeline_settings"]
taxon = data["taxon"]
quast = data["quast"]
amr_finder = data["amr"]["amrfinder"]
amrs = sorted(amr_finder, key=lambda x: x['Gene symbol'])
qc_warnings = qc["messages"]
qc_pass = qc["pass"]
qc_warn = qc["warn"]
qc_fail = qc["fail"]

taxkit = data["taxonkit"]
taxkit_majority = taxkit["species"][0]
majority_species = taxkit_majority["species"]
majority_fraction = round(taxkit_majority["fraction"] * 100, 2)
minority_species = False
minority_fraction = False

if len(taxkit["species"]) > 1:
    taxkit_minority = taxkit["species"][1]
    if taxkit_minority["fraction"] >= 5.0:
        minority__species = taxkit["species"][1]
        minority_fraction = round(taxkit_minority["fraction"] * 100, 2)

mlst = data["mlst"]
serotype = data["serotype"]
if "plasmids" in data:
    plasmids = data["plasmids"]
else:
    plasmids = []

coverage = data["mosdepth"]["total"]["mean"]
coverage_status = get_status("coverage_total_mean", qc)

if "illumina" in data["mosdepth"]:
    coverage_illumina = data["mosdepth"]["illumina"]["mean"]
else:
    coverage_illumina = None

if "fastp" in data:
    has_illumina = True
    q30_rate = round(data["fastp"]["summary"]["before_filtering"]["q30_rate"], 2)*100
    read_length = data["fastp"]["read1_before_filtering"]["total_cycles"]
    insert_size = data["fastp"]["insert_size"]["peak"]
    total_bases = round(data["fastp"]["read1_before_filtering"]["total_bases"]/1000000, 0)
    assembly_size = round(float(quast["Total length"] / 1000000), 3)
else:
    q30_rate = None
    read_length = None
    insert_size = None
    total_bases = None
    assembly_size = None

confindr = data["confindr"]

illumina_contam_info = ""

if confindr["illumina"] and len(confindr["illumina"][0]) > 0:
    confindr_illumina = data["confindr"]["illumina"][0][0]
    illumina_contam_info = "inter-species" if ":" in confindr_illumina["Genus"] else f"Kontaminierende SNVs: {confindr_illumina['NumContamSNVs']}"

##############################
# PDF construction starts here
##############################
disclaimer = f"Anlage zur Gesamtgenome-Sequenzierung von {sample}"

content.append(Paragraph(disclaimer, styles["Normal"]))
content.append(Spacer(1, 12))

header = "Bericht zur Gesamtgenom-Sequenzierung mittels NGS (M-2448)"
page_header = f"{sample} - {header}"

content.append(Paragraph(header, styles["H1"]))
content.append(Spacer(1, 12))

subheader = "Qualitätsbewertung und Charakterisierung"
content.append(Paragraph(subheader, styles["H2"]))

content.append(Spacer(1, 12))

key_translation = {
    "Total length": "Gesamtgröße",
    "# contigs": "Anzahl Contigs",
    "N50": "N50",
    "# contigs (>= 1000 bp)": "Anzahl Contigs > 1kb",
    "GC (%)": "GC Gehalt (%)",
    "Largest contig": "Größtes Contig",
    "Duplication ratio": "Duplikations-Ratio"
}

####################
# Section: Uebersicht
####################

content.append(Spacer(1, 4))

d = Drawing(100, 0.5)
d.add(Line(0, 0, 450, 0))
content.append(d)
content.append(Spacer(1, 10))

content.append(Paragraph(f"Pipeline: {settings['pipeline']}", styles["Info"]))
content.append(Paragraph(f"Version: {settings['version']}", styles["Info"]))

content.append(Spacer(1, 20))

content.append(Paragraph("Übersicht", styles["H2_bg"]))
content.append(Spacer(1, 10))

mlst = data["mlst"][0]
serotypes = data["serotype"]

summary = []

summary.append(["Untersuchte Probe", sample])
summary.append(["Status der Sequenzierung*", Paragraph(qc["call"], status_styles[qc["call"]])])
summary.append(["Mittlere Sequenziertiefe", Paragraph(f"{coverage_illumina} X", styles["Normal"])])
summary.append(["Ermitteltes Taxon", Paragraph(f"<i>{taxon}</i>", styles["Taxon"])])
summary.append(["Assemblygröße (Mb)", Paragraph(f"{assembly_size}", styles["Normal"])])
summary.append(["Contigs > 1kb", quast["# contigs (>= 1000 bp)"]])
summary.append(["Plasmide", f"{len(plasmids)}"])
if (mlst):
    summary.append(["MLST Typ (Schema)**", f"{mlst['sequence_type']} ({mlst['scheme']})"])

if (len(serotypes) > 0):
    this_sero = get_serotype(serotypes)
    summary.append(["Serotyp (Software)**", f"{this_sero['serotype']} ({this_sero['tool']})"])
    if (this_sero["pathotype"]):
        summary.append(["Pathotyp", this_sero["pathotype"]])

if "confindr_illumina" in qc_fail:
    summary.append(["Kontamination (Sequenzen)", illumina_contam_info])

if "taxonkit_genus_fraction" in qc_fail:

    summary.append(["Kontamination (Assembly)", f"{majority_genus} ({majority_fraction} %)"])

summary.append(["Datum der Auswertung", run_date])

summary_table = Table(summary, colWidths=[7 * cm, 8 * cm], splitByRow=1, hAlign='LEFT')

summary_table.setStyle([
    ('LINEABOVE', (0, 1), (-1, -1), 0.25, colors.black),
    ('VALIGN', (0, 0), (-1, -1), 'TOP')
])

content.append(summary_table)
content.append(Spacer(1, 20))

content.append(Paragraph(f"* <b>pass</b>: keine Beanstandungen, <b>warn</b>: Wert(e) leicht außerhalb der Norm, <b>fail</b>: Wert(e) außerhalb der Norm, Probe kann ggf. nicht verwendet werden", styles["Info"]))
content.append(Spacer(1, 5))
content.append(Paragraph(f"** Nicht Teil der Validierung/Akkreditierung der Methode.", styles["Info"]))
content.append(Spacer(1, 20))


# ~~~~~~~~~~~~~~~~~~~~~~~
# Rohdaten Metriken
# ~~~~~~~~~~~~~~~~~~~~~~~

content.append(Paragraph("Rohdaten Metriken", styles["H2_bg"]))
content.append(Spacer(1, 10))

info = "Metriken zur Beschreibung der verwendeten Rohdaten"

content.append(Paragraph(info, styles["Info"]))
content.append(Spacer(1, 10))

raw_data = []
raw_data = [[Paragraph("Metrik", styles["Bold"]), Paragraph("Wert", styles["Bold"])]]

raw_data.append(["Readlänge (Basen)", Paragraph(f"{read_length}", styles["Normal"])])
raw_data.append(["Basenmenge (Millionen)", Paragraph(f"{total_bases}", styles["Normal"])])
raw_data.append(["Mittlere Sequenziertiefe (X)", Paragraph(f"{coverage_illumina}", styles["Normal"])])
raw_data.append(["Anteil Q30 Basen (%)", Paragraph(f"{q30_rate}", styles["Normal"])])
raw_data.append(["Mittlere Fragmentgröße (Basen)", Paragraph(f"{insert_size}", styles["Normal"])])

raw_data_table = Table(raw_data, colWidths=[7 * cm, 8 * cm], splitByRow=1, hAlign='LEFT')

raw_data_table.setStyle([
    ('LINEABOVE', (0, 1), (-1, -1), 0.25, colors.black),
    ('VALIGN', (0, 0), (-1, -1), 'TOP')
])

content.append(raw_data_table)

content.append(PageBreak())

content.append(Spacer(1, 20))
content.append(Paragraph(page_header, styles["header"]))
content.append(Spacer(1, 10))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Assembly Metriken
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

content.append(Paragraph("Assembly Metriken", styles["H2_bg"]))
content.append(Spacer(1, 10))

info = "Metriken zur Beschreibung der rekonstruierten Genomsequenz"

content.append(Paragraph(info, styles["Info"]))
content.append(Spacer(1, 10))

quast_metrics = [[Paragraph("Metrik", styles["Bold"]), Paragraph("Wert", styles["Bold"])]]

quast_keys = [
    "Total length", "# contigs", "N50", "GC (%)", "Duplication ratio"
]

for key in quast_keys:
    translation = key_translation[key] if key in key_translation else key
    value = quast[key]
    status_key = qc_lookups[key] if key in qc_lookups else None
    qc_status = get_status(status_key, qc) if status_key else "missing"

    quast_metrics.append([Paragraph(translation, styles["Normal"]), Paragraph(f"{value}", styles["Normal"])])

busco = data["busco"]
busco_total = int(busco["dataset_total_buscos"])
busco_complete = int(busco["C"])
busco_completeness = round(float(busco_complete / busco_total), 2) * 100
busco_duplicates = int(busco["D"])
busco_duplication = round(float(busco_duplicates / busco_total), 2) * 100

busco_complete_status = get_status("busco_completeness", qc)
busco_duplication_status = get_status("busco_duplicates", qc)

quast_metrics.append(["BUSCO Gene vollständig (%)", Paragraph(f"{busco_completeness}", styles["Normal"])])
quast_metrics.append(["BUSCO Gene dupliziert (%)", Paragraph(f"{busco_duplication}", styles["Normal"])])

quast_metrics_table = Table(quast_metrics, colWidths=[8 * cm, 4 * cm], splitByRow=1, hAlign='LEFT')

quast_metrics_table.setStyle([
    ('LINEABOVE', (0, 1), (-1, -1), 0.25, colors.black),
    ('VALIGN', (0, 0), (-1, -1), 'TOP')
])

content.append(quast_metrics_table)
content.append(Spacer(1, 10))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Kontaminierungen
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

content.append(Paragraph("Kontaminationskontrolle", styles["H2_bg"]))
content.append(Spacer(1, 10))

info = "Metriken zur Bestimmung eventueller Kontaminationen"

content.append(Paragraph(info, styles["Info"]))
content.append(Spacer(1, 10))

contaminations = []
contaminations = [[Paragraph("Metrik", styles["Bold"]), Paragraph("Wert", styles["Bold"])]]

confindr_illumina_status = get_status("confindr_illumina", qc)

contaminations.append(["Illumina Sequenzkontamination", (Paragraph(f"{illumina_contam_info}", status_styles[confindr_illumina_status]))])

taxonkit_status = get_status("taxonkit_genus_fraction", qc)
contaminations.append(["Assembly - primäre Spezies", (Paragraph(f"<i>{majority_species}</i> ({majority_fraction}%)",status_styles[taxonkit_status]))])
if minority_species:
    contaminations.append(["Assembly: Sekundäre Spezies", (Paragraph(f"{minority_species} ({minority_fraction}%)", styles["Normal"]))])

contaminations_table = Table(contaminations, colWidths=[8 * cm, 8 * cm], splitByRow=1, hAlign='LEFT')
contaminations_table.setStyle([
    ('LINEABOVE', (0, 1), (-1, -1), 0.25, colors.black),
    ('VALIGN', (0, 0), (-1, -1), 'TOP')
])

content.append(contaminations_table)
content.append(Spacer(1, 10))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# QC Metriken
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

content.append(Spacer(1, 20))
content.append(Paragraph("Interne Qualitätsmetriken", styles["H2_bg"]))
content.append(Spacer(1, 10))

info = "Pipeline-interne Schwellenwerte und Klassifikation"

content.append(Paragraph(info, styles["Info"]))
content.append(Spacer(1, 10))

qc_entries = [[Paragraph("Metrik", styles["Bold"]), Paragraph("Status", styles["Bold"])]]

for item in sorted(qc_pass):
    qc_entries.append([Paragraph(item, styles["Normal"]), Paragraph("pass", status_styles["pass"])])


for item in sorted(qc_warn):
    qc_entries.append([Paragraph(item, styles["Normal"]), Paragraph("warn", status_styles["warn"])])

for item in sorted(qc_fail):
    qc_entries.append([Paragraph(item, styles["Normal"]), Paragraph("fail", status_styles["fail"])])

qc_table = Table(qc_entries, colWidths=[8 * cm, 4 * cm], splitByRow=1, hAlign='LEFT')

qc_table.setStyle([
    ('LINEABOVE', (0, 1), (-1, -1), 0.25, colors.black),
    ('VALIGN', (0, 0), (-1, -1), 'TOP')
])

content.append(qc_table)
content.append(Spacer(1, 20))

content.append(Paragraph(f"* <b>pass</b>: keine Beanstandungen, <b>warn</b>: Wert(e) leicht außerhalb der Norm, <b>fail</b>: Wert(e) außerhalb der Norm, Probe kann ggf. nicht verwendet werden", styles["Info"]))
content.append(Spacer(1, 20))

content.append(PageBreak())

content.append(Spacer(1, 20))
content.append(Paragraph(page_header, styles["header"]))
content.append(Spacer(1, 10))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Charakterisierung
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

content.append(Paragraph("Resistenz- und Virulenzgene (nicht akkreditiert)", styles["H2_bg"]))
content.append(Spacer(1, 10))

characterization = [[Paragraph("Gen", styles["Bold"]), Paragraph("Beschreibung", styles["Bold"]), Paragraph("Klasse", styles["Bold"]), Paragraph("Typ", styles["Bold"])]]

for amr in amrs:
    characterization.append([Paragraph(amr['Gene symbol'], styles["Bold"]), Paragraph(amr['Sequence name'], styles["Normal"]), Paragraph(amr['Class'], styles["Normal"]), Paragraph(amr['Element type'], styles["Normal"])])

characterization_table = Table(characterization, colWidths=[2 * cm, 8 * cm, 3 * cm, 3 * cm], splitByRow=1, hAlign='LEFT')

characterization_table.setStyle([
    ('LINEABOVE', (0, 1), (-1, -1), 0.25, colors.black),
    ('VALIGN', (0, 0), (-1, -1), 'TOP')
])

content.append(characterization_table)
content.append(Spacer(1, 20))

content.append(PageBreak())

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Pipeline Einstellungen
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

content.append(Paragraph("Einstellungen", styles["H2_bg"]))
content.append(Spacer(1, 10))

software = [[Paragraph("Parameter", styles["Bold"]), Paragraph("Einstellung", styles["Bold"])]]
for key, values in settings.items():
    if type(values) is not dict:
        software.append([key, Paragraph(str(values), styles["table"])])

software_table = Table(software, colWidths=[7 * cm, 8 * cm], splitByRow=1, hAlign='LEFT')

software_table.setStyle([
    ('VALIGN', (0, 0), (-1, -1), 'TOP'),
    ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
    ('TOPPADDING', (0, 0), (-1, -1), 1)
])

content.append(software_table)

pdf.build(content)
