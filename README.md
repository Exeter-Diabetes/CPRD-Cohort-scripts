# CPRD-Katie-MASTERMIND-Scripts

MASTERMIND (MRC APBI Stratification and Extreme Response Mechanism IN Diabetes) is a UK Medical Research Council funded (MR/N00633X/1 and MR/W003988/1) study consortium exploring stratified (precision) treatment in Type 2 diabetes. Part of this work uses data from the Clinical Practice Research Datalink (CPRD); originally the 'GOLD' version which was processed as per [Rodgers et al. 2017](https://bmjopen.bmj.com/content/7/10/e017989). Papers produced from this dataset include:
*
*
*
*
*

Recently we have recreated the above processing pipeline in CPRD Aurum, and this repository contains the scripts used to do this. Raw text files from CPRD were imported into a MySQL database using a custom-built package ([aurum](https://github.com/drkgyoung/Exeter_Diabetes_aurum_package)) built by Dr Robert Challen. This package also includes functions to allow easy querying of the MySQL tables from R, using the 'dbplyr' tidyverse package. Codelists used for querying the data (denoted as 'codes$\[codelist_name\]' in scripts) can be found in our [CPRD-Codelists repository](https://github.com/Exeter-Diabetes/CPRD-Codelists).


## CPRD Aurum extract details
Patients with a diabetes medcode ([full list here](https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Extract-details/diab_med_codes_2020.txt)) in the Observation table were extracted from the October 2020 CPRD Aurum release. See below for full inclusion criteria:

<img src="https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Extract-details/download_details2.PNG" width="370">
<img src="https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Extract-details/download_details1.PNG" width="700">
