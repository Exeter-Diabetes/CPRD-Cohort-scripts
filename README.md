# CPRD Aurum Cohort scripts

## Introduction

This repository contains the R scripts used by the Exeter Diabetes team to produce three cohorts and their associated biomarker/comorbidity/sociodemographic data from a CPRD Aurum dataset: 
* An **'at-diagnosis'** cohort
* A **prevalent** cohort (registered at 01/02/2020)
* A **treatment response** (MASTERMIND) cohort (those initiating diabetes medications)

The below diagram outlines the data processing steps involved in creating these cohorts.

```mermaid
graph TD;
    A["<b>CPRD Aurum October 2020 release</b> <br> with linked HES APC, patient IMD, and ONS death data"] --> |"Unique patients with a diabetes-related medcode between 01/01/2004-06/11/2020 and >=1 year data prior and after"| B["<b>Our extract</b>: n=1,480,985*"]
    B -->|"With a diabetes QOF code with a valid date** (quality check to remove those without diabetes)"|C["n=1,138,193"]
    C --> |"With no codes for non-T1/T2 diabetes types (any date)"|D["n=1,120,085"]
    D --> |"Inconsistencies in diabetes type suggesting <br> coding errors or unclassifiable"|E["n=14"]
    D --> F["<b>T1T2 cohort</b>: n=1,120,071"]
    F --> G["<b>01 At-diagnosis cohort</b>: <br> n= <br> Index date=diagnosis date"]
    F --> H["<b>02 Prevalent cohort</b>: <br> n= <br> Actively registered on 01/02/2020 <br> Index date=diagnosis date"]
    F --> I["<b>03 Treatment response (MASTERMIND) cohort</b>: <br> n= <br> With script for diabetes medication <br> Index date=drug start date"]
```
\* Extract actually contained n=1,481,294 unique patients (1,481,884 in total but some duplicates) but included n=309 with registration start dates in 2020 (which did not fulfil the extract criteria of having a diabetes-related medcode between 01/01/2004-06/11/2020 and >=1 year of data after this; some of these were also not 'acceptable' by [CPRD's definition](https://cprd.com/sites/default/files/2023-02/CPRD%20Aurum%20Glossary%20Terms%20v2.pdf)). See next section for further details on the extract.
&nbsp;

\** A valid date is an obsdate (for medcodes) which is no earlier than the patient's date of birth (no earlier than the month of birth if date of birth is not available; no earlier than full date of birth if this is available), no later than the patient's date of death (earliest of cprd_ddeath (Patient table) and dod/dor where dod not available (ONS death data)) where this is present, no later than deregistration where this is present, and no later than the last collection date from the Practice.

&nbsp;

## Extract details
Patients with a diabetes-related medcode ([full list here](https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Extract-details/diab_med_codes_2020.txt)) in the Observation table were extracted from the October 2020 CPRD Aurum release. See below for full inclusion criteria:

<img src="https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Extract-details/download_details1.PNG" width="370">

&nbsp;

<img src="https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Extract-details/download_details2.PNG" width="700">

&nbsp;


## Script overview

The below diagram shows the R scripts (in grey boxes) used to create the final cohorts (at-diagnosis, prevalent, and treatment response).

```mermaid
graph TD;
    A["<b>Our extract</b> <br> with linked HES APC, patient IMD, and ONS death data"] --> |"all_t1t2_cohort <br> & all_patid_ethnicity"|B["<b>T1T2 cohort</b> with static <br> patient data including <br> ethnicity and IMD*"]
    A-->|"all_patid_ckd_stages"|C["<b>Longitudinal CKD stages</b> <br> for all patients"]
    A-->|"baseline_biomarkers <br> (requires index date)"|E["<b>Biomarkers</b> <br> at index date"]
    A-->|"comorbidities <br> (requires index date)"|F["<b>Comorbidities</b> <br> at index date"]
    A-->|"smoking <br> (requires index date)"|G["<b>Smoking status</b> <br> at index date"]
    A-->|"alcohol <br> (requires index date)"|H["<b>Alcohol status</b> <br> at index date"]
    A-->|"ckd_stage"|I["<b>CKD stage</b <br> at index date"]
    C-->|"ckd_stage"|I
    B-->|"final_merge"|J["<b>Final cohort dataset</b>"]
    E-->|"final_merge"|J
    F-->|"final_merge"|J
    G-->|"final_merge"|J
    H-->|"final_merge"|J
    I-->|"final_merge"|J
```
\*IMD=Index of Multiple Deprivation; 'static' because we only have data from 2015.

&nbsp;

Each of the three final cohorts (at-diagnosis, prevalent, and treatment response) contains static patient data e.g. ethnicity, IMD and diabetes type from the T1T2 cohort dataset, plus biomarker, comorbidity, and sociodemographic (smoking/alcohol) data at the (cohort-specific) index date.


This directory contains the scripts which are common to all three cohorts: 'all_patid_ckd_stages', 'all_patid_ethnicity', and 'all_t1t2_cohort'. These pull out static patient characteristics or features based on longitudinal data which may go beyond the index date of the cohorts (e.g. all_patid_ethnicity uses ethnicity codes from all time for each patient, which may occur later than the index date for a cohort).


In addition, this directory contains templates for the scripts which pull out data relative to the cohort index dates ('baseline_biomarkers', 'comorbidities', 'smoking', 'alcohol', 'ckd_stage' and 'final_merge'). The final cohorts each use tailored versions of these to account for the different index dates, the different biomarkers/comorbidities required for the different cohorts, and different additional inclusion/exclusion criteria which are applied in the 'final_merge' script. In addition to these differences, the cohorts have different additional scripts which pull in additional information e.g. the treatment response cohort also has biomarker responses (6/12 month post-index) and post-index comorbidity occurrences, used to evaluate treatment response.

The exact 'tailored' and additional scripts used to create each cohort dataset can be found in the relevant subdirectory: link link link.

&nbsp;

## Scripts in this directory

| Script description | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Outputs&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; |
| ---- | ---- |
| **all_patid_ckd_stages**:<br /> uses eGFR calculated from serum creatinine () to define longitudinal CKD stages for all patids using our algorithm |  **all_patid_ckd_stages_from_algorithm**:  1 row per patid, with onset of different CKD stages in wide format |
| **all_patid_ethnicity**:<br />pulls biomarkers value at drug start dates  | **mm_full_{biomarker}\_drug_merge**: all longitudinal biomarker values merged with mm_drug_start_stop with additional variables (timetochange, timeaddrem, multi_drug_start) from mm_combo_start_stop - gives 1 row per biomarker reading-drug period combination<br />**mm_baseline_biomarkers**: as per mm_drug_start_stop, with all biomarker values at drug start date where available (including HbA1c and height) |
| **03_mm_response_biomarkers**: find biomarkers values at 6 and 12 months after drug start | **mm_response_biomarkers**: as per mm_drug_start_stop, except only first instance (drug_instance==1) included, with all biomarker values at 6 and 12 months where available (including HbA1c, not height). Response HbA1cs missing where changed diabetes meds <= 61 days before drug start (timeprevcombo<=61) |
| **04_mm_comorbidities**: finds onset of comorbidities relative to drug start dates | **mm_full_{comorbidity}\_drug_merge**: all longitudinal comorbidity code occurrences merged with mm_drug_start_stop on patid - gives 1 row per comorbidity code occurrence-drug period combination<br />**mm_comorbidities**: as per mm_drug_start_stop, with earliest predrug code occurrence, latest predrug code occurrence, and earliest postdrug code occurrence for all comorbidities (where available). Also has whether patient had hospital admission in previous year to drug start |
| **05_mm_ckd_stages**: finds onset of CKD stages relative to drug start dates | **all_patid_ckd_stages_from_algorithm**: 1 row per patid, with onset of different CKD stages in wide format<br />**mm_ckd_stages**: as per mm_drug_start_stop, with baseline CKD stage at drug start date where available and post-drug CKD outcomes (onset of CKD stage 3-5, onset of CKD stage 5, composite of fall in eGFR of >=40% or CKD stage 5) where available |
| **06_mm_non_diabetes_meds**: dates of various non-diabetes medication prescriptions relative to drug start dates | **mm_non_diabetes_meds**: as per mm_drug_start_stop, with earliest predrug script, latest predrug script, and earliest postdrug script for all non-diabetes medications where available |
| **07_mm_smoking**: finds smoking status at drug start dates | **mm_smoking**: as per mm_drug_start_stop, with smoking status and QRISK2 smoking category at drug start date where available |
| **08_mm_discontinuation**: defines whether drug was discontinued within 3/6 months | **mm_discontinuation**: as per mm_drug_start_stop, with discontinuation variables added |
| **09_mm_death_causes**: adds variables on causes of death | **mm_death_causes**: 1 row per patid in ONS death data table, with primary and secondary death causes plus variables for whether CV/heart failure are primary/secondary causes |
| **10_mm_final_merge**: pulls together results from other scripts to produce final dataset for a Type 2 diabetes cohort | **mm_{today's date}\_t2d_1stinstance**: as per mm_drug_start_stop, but includes first instance (druginstance==1) drug periods only, and excludes those starting within 91 days of registration. Only includes patids with T2D and HES linkage. Adds in variables from other scripts (e.g. comorbidities, non-diabetes meds), and adds some additional ones.<br />**mm_{today's date}\_t2d_all_drug_periods**: as per mm_drug_start_stop (i.e. all instances, not excluding those initiated within 91 days of registration), for patids with T2D and HES linkage (the same cohort as the mm_{today's date}\_t2d_1stinstance table) |
| **all_patid_ethnicity_table**: ethnicities of all patids in download | **all_patid_ethnicity**: 1 row per patid with 5-category, 16-category, and QRISK2-category ethnicity | 
| **all_patid_townsend_deprivation_score**: approximate Townsend Deprivation Scores of all patids in download | **all_patid_townsend_score**: approximate Townsend Deprivation Scores derived from Index of Multiple Deprivation scores |
| **all_t1t2_cohort_table**: table of patids meeting the criteria for our mixed Type 1/Type 2 diabetes cohort plus additional patient variables | **all_t1t2_cohort**: 1 row per patid of those in the T1/T2 cohort, with diabetes diagnosis dates, DOB, gender, ethnicity etc. |
