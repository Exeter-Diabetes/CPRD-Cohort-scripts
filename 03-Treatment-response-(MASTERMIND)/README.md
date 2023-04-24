# Treatment response cohort 

The treatment response cohort consists of all those in the diabetes cohort (n=1,138,179; see [flow diagram](https://github.com/Exeter-Diabetes/CPRD-Cohort-scripts/blob/main/README.md#introduction)) who have at least one script for a glucose-lowering medication (drug classes: acarbose, DPP4-inhibitor, glinide, GLP1-receptor agonist, metformin, SGLT2-inhibitor, sulphonylurea, thiazolidinedione, or insulin). The index date is the drug start date of the glucose-lowering medication. Patients can appear in the cohort multiple times with different drug classes or if they stop and then re-start a medication. Scripts are processed by drug class (i.e. changes from one medication to another within the same class are ignored). The final dataset contains biomarker, comorbidity, sociodemographic and medication info at drug start dates, as well as 6-/12-month biomarker response.

MASTERMIND (MRC APBI Stratification and Extreme Response Mechanism IN Diabetes) is a UK Medical Research Council funded (MR/N00633X/1 and MR/W003988/1) study consortium exploring stratified (precision) treatment in Type 2 diabetes. Part of this work uses the Type 2 subset of the treatment response cohort. Originally CPRD GOLD was used and processed as per [Rodgers et al. 2017](https://bmjopen.bmj.com/content/7/10/e017989). Recently we have recreated this processing pipeline in CPRD Aurum, and this directory contains the scripts used to do this. MASTERMIND papers based on the previous GOLD dataset can be found at the bottom of this page.

&nbsp;

## Script overview

The below diagram shows the R scripts (in grey boxes) used to create the treatment response cohort.

```mermaid
graph TD;
    A["<b>Our extract</b> <br> with linked HES APC, patient IMD, and ONS death data"] --> |"all_diabetes_cohort <br> & all_patid_ethnicity"|B["<b>Diabetes cohort<br></b> with static patient <br>data including <br>ethnicity and IMD*"]
    A-->|"all_patid_townsend_<br>deprivation_score"|N["<b>Townsend<br> Deprivation<br>score</b> for<br> all patients"]
    A-->|"09_mm_<br>death_causes"|O["<b>Death<br>causes</b>"]
    A-->|"01_mm_drug_sorting_and_combos"|H["Drug start (index) and stop dates"]

    A---Y[ ]:::empty
    H---Y
    Y-->|"02_mm_baseline_<br>biomarkers"|E["<b>Biomarkers</b> <br> at drug <br> start date"]
    
    A---T[ ]:::empty
    H---T
    T-->|"03_mm_response_<br>biomarkers"|L["<b>Biomarkers</b> <br> 6/12 months <br> after drug <br>start date"]
    
    A---W[ ]:::empty
    H---W
    W-->|"04_mm_<br>comorbidities"|F["<b>Comorbidities</b> <br> at drug <br> start date"]
    
    H---U[ ]:::empty
    A---U
    U-->|"06_mm_non_<br>diabetes_meds"|M["<b>Non-diabetes <br>medications</b> <br> at drug <br> start date"]
    
    H---X[ ]:::empty
    A---X
    X-->|"07_mm_smoking"|G["<b>Smoking status</b> <br> at drug <br> start date"]
    
    H-->|"08_mm_discontinuation"|V["<b>Discontinuation</b><br> information"]
    
    A-->|"all_patid_ckd_stages"|C["<b>Longitudinal CKD <br> stages</b> for all <br> patients"]
    H---Z[ ]:::empty
    C---Z
    Z-->|"05_mm_ckd_stages"|I["<b>CKD stage </b> <br> at drug <br> start date"]
    
    
    B-->|"10_mm_<br>final_merge"|J["<b>Final cohort dataset</b>"]
    N-->|"10_mm_<br>final_merge"|J
    O-->|"10_mm_<br>final_merge"|J
    E-->|"10_mm_<br>final_merge"|J
    L-->|"10_mm_<br>final_merge"|J
    F-->|"10_mm_<br>final_merge"|J
    M-->|"10_mm_<br>final_merge"|J  
    G-->|"10_mm_<br>final_merge"|J
    V-->|"10_mm_<br>final_merge"|J
    I-->|"10_mm_<br>final_merge"|J  
```
\*IMD=Index of Multiple Deprivation; 'static' because we only have data from 2015 so only 1 value per patient.

The scripts shown in the above diagram (in grey boxes) can be found in this directory, except those which are common to the other cohorts (all_diabetes_cohort, all_patid_ethnicity, and all_patid_ckd_stages) which are in the upper directory of this repository.

&nbsp;

## Script details

'Drug' refers to diabetes medications unless otherwise stated, and the drug classes analysed by these scripts are acarbose, DPP4-inhibitors, glinides, GLP1 receptor agonists, metformin, SGLT2-inhibitors, sulphonylureas, thiazolidinediones, and insulin. 'Outputs' are the primary MySQL tables produced by each script. See also notes on the [aurum package](https://github.com/Exeter-Diabetes/CPRD-analysis-package) and [CPRD-Codelists respository](https://github.com/Exeter-Diabetes/CPRD-Codelists) in the upper directory of this repository ([here](https://github.com/Exeter-Diabetes/CPRD-Cohort-scripts#script-details)).

&nbsp;

| Script description | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Outputs&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; |
| ---- | ---- |
| **01_mm_drug_sorting_and_combos**:<br />processes raw diabetes medication prescriptions from the CPRD Drug Issue table, combining successive prescriptions for the same drug class into continuous periods with start and stop dates |  **mm_ohains**: all prescriptions for diabetes medications, with duplicates for patid/date/drugclass removed, and coverage calculated. 1 row per patid/date/drugclass<br />**mm_all_scripts_long**: as per mm_ohains but with additional variables like number of drug classes started on that day (numstart)<br />**mm_all_scripts**: reshaped wide version of mm_all_scripts_long, with one row per patid/date<br />**mm_drug_start_stop**: one row per continuous period of use of each patid/drugclass, with start and stop dates, drugline etc.<br />**mm_combo_start_stop**: one row per continuous period of patid/drug combination, including variables like time until next drug class added or removed |
| **02_mm_baseline_biomarkers**:<br />pulls biomarkers value at drug start dates  | **mm_full_{biomarker}\_drug_merge**: all longitudinal biomarker values merged with mm_drug_start_stop with additional variables (timetochange, timeaddrem, multi_drug_start) from mm_combo_start_stop - gives 1 row per biomarker reading-drug period combination<br />**mm_baseline_biomarkers**: as per mm_drug_start_stop, with all biomarker values at drug start date where available (including HbA1c and height) |
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

&nbsp;


# Data Dictionary

Intermediate tables and variables used for working not included. Self-explanatory variables like patid and drugclass not included.

## Script: 01_mm_drug_sorting_and_combos
### Table: mm_ohains / mm_all_scripts_long (ohains lacks dstart/dstop/num* variables)

1 line per patid / date / drug class (for which there is a prescription) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| quantity | number of tablets/items in prescriptions | provided by CPRD in drug issue table, directly from GP records<br />if 0, assume missing<br />if multiple prescriptions for same patid/date/drug, take mean |
| daily_dose | number of tablets/items prescribed per day | provided by CPRD (in dosage lookup ('common doses') - need to merge with dosageid in Drug Issue table), 'derived using CPRD algorithm based on free text'<br />if 0, assume missing<br />if multiple prescriptions for same patid/date/drug, take mean |
| duration | number of days prescription is for | provided by CPRD in drug issue table, no info on source so presumably from GP records<br />if 0, assume missing<br />if multiple prescriptions for same patid/date/drug, take mean |
| coverage | days of meds for that script | quantity/daily_dose if neither are missing, or use duration<br />NB: very high missingness in Aurum (~60%) |
| drugsubstances | drug substances within that class prescribed on that date | from [drug substance class lookup](https://github.com/Exeter-Diabetes/CPRD-Katie-MASTERMIND-Scripts/blob/main/Scripts/drug_substance_class_lookup.txt)<br />if multiple prescriptions for same patid/date/drug with different drug substances, combined using ' & ' as a separator |
| dstart | whether date is start date for that drug class (binary 0 or 1) | dstart=1 if it is the earliest script of that drug class for that person, or if previous script was >183 days (6 months) prior |
| dstop | whether date is stop for that drug class (binary 0 or 1) | dstop=1 if it is the last script of that drug class for that person, or if next script is >183 days (6 months) after |
| numpxdate | number of different drug classes prescribed that day (duplicated within patid/date) | |
| numstart | number of drug classes started on that day (duplicated within patid/date) | sum of dstart on that day |
| numstop | number of drug classes stopped on that day (duplicated within patid/date) | sum of dstop on that day |

&nbsp;

### Table: mm_all_scripts

1 line per patid / date (drugclass specific variables in wide format) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| cu_numstart | cumulative sum of numstart up to this date | |
| cu_numstop | cumulative sum of numstop up to this date | |
| numdrugs | number of drug classes patient is on at that date including ones stopped on that date | calculated as: cu_numstart - cu_numstop + numstop (add numstop so includes drug stopped on that day<br />NB: numdrugs2 is identical - calculated as sum of binary drug class columns (see next row) to check |
| Acarbose / DPP4 / Glinide / GLP1 / MFN / SGLT2 / SU / TZD / INS | binary variable of whether patient taking that drugclass on that date (regardless of whether or not prescribed on that date) | calculated using dstart and dstop vars for that particular drug class: 1 if cumsum(dstart)>cumsum(dstop) | dstart==1 | dstop==1 |
| INS_startdate | start date for insulin which is being taken on this date | uses dstart=1 - see above |
| INS_stopdate | stop date for insulin which is being taken on this date | uses dstop=1 - see above |
| drugcombo | combination of drug classes patient is on at that date | made by concatenating names of drug classes which patient is on at that date (from binary variables; separated by '\_') |
| dcstart | whether date is start date for drug combo | uses drugcombo variable: 1 if it is the earliest instance of that drug combo for that person, or if previous script was >183 days (6 months) prior |
| dcstop | whether date is stop for drug combo | uses drugcombo variable: 1 if it is the last instance of that drug combo for that person, or if next script is >183 days (6 months) after |
| timetolastpx | time from date to last prescription date for patient (in days) | |

&nbsp;

### Table: mm_drug_start_stop

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| dstartdate | drug class start date | uses dstart=1 - see above |
| dstopdate | drug class stop date | uses dstop=1 - see above |
| dstopdatepluscov | drug class stop date + coverage from last prescription | |
| drugsubstances | see above - based on what they got for their first prescription only; some people have >1 type if they got prescriptions for more than one type on that day | NB: each drug period has drug substance defined by whatever they were prescribed on the first day of starting that drug class. Validation analysis has shown that the percentage of scripts within each drug period with the same drug substance as the first script is >80% for all drug substances except the older SUs (glibenclamide, tolbutamid, chlorpropamid, gliquidone, tolazamide), rosiglitazone, and the older GLP1s (exenatide, lixisenatide, albiglutide), as people tend to be switched to newer agents (gliclazide for the SUs, pioglitazone for rosigliltazone, liraglutide for the GLP1s) during the drug period |
| timeondrug | dstopdate-dstartdate (in days) | |
| timeondrugpluscov | dstoppluscovdate-dstartdate (in days) | |
| drugorder | order within patient | e.g. patient takes MFN, SU, MFN, TZD in that order = 1, 2, 3, 4 |
| drugline_all / drugline | drug line<br />drugline_all is not missing for any drug periods<br />In final merge script, 'drugline' is the same as 'drugline_all' except it is set to missing if diabetes diagnosis date < registration (this is the only reason why this variable would be missing) | just takes into account first instance of drug e.g. patient takes MFN, SU, MFN, TZD in that order = 1, 2, 1, 4<br />if multiple drug classes started on same day, use minimum drug line for both |
| druginstance | 1st, 2nd, 3rd etc. period of taking this specific drug class | |

&nbsp;

### Table: mm_combo_start_stop

1 line per patid / drug combo instance (continuous period of drug combo use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| dcstartdate | drug combo start date | uses dcstart - see above |
| dcstopdate | drug combo stop date | uses dcstop - see above |
| drugcomboorder | order within patient | e.g. patient takes MFN only, MFN+SU, MFN+SU+DPP4 in that order = 1, 2, 3 |
| nextdcdate | date of next drug combination | doesn't include breaks i.e. when patient on none of the drug classes |
| add | number of drug classes added compared to previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />0 if none added / no previous drug combo as this is the first |
| rem | number of drug classes removed compared to previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />0 if none removed / no previous drug combo as this is the first |
| swap | 1 if at least one drug class added and at least one drug class removed compared to previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | uses add and rem<br />0 if no swap (i.e. drugs only added or removed) / no previous drug combo as this is the first |
| adddrug | names of drug classes added from previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />NA if none added / no previous drug combo as this is the first |
| remdrug | names of drug classes removed from previous drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />NA if none removed / no previous drug combo as this is the first |
| nextadd | number of drug classes added to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />0 if none added / no next drug combo as this is the last before end of prescriptions |
| nextrem | number of drug classes added to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />0 if none removed / no next drug combo as this is the last before end of prescriptions |
| nextswap | 1 if at least one drug class added and at least one drug class removed to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | uses nextadd and nextrem<br />0 if no swap (i.e. drugs only added or removed) / no next drug combo as this is the last before end of prescriptions |
| nextaddrug | names of drug classes added to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />NA if none added / no next drug combo as this is the last before end of prescriptions |
| nextremdrug | names of drug classes removed to get next drug combo (doesn't take into account breaks when patient is on no diabetes meds) | calculated using binary {drugclass} variables - see above<br />NA if none removed / no next drug combo as this is the last before end of prescriptions |
| drugchange | what change from previous drug combo to present one represents: add / remove / swap / (no previous combo as this is the) start of px / restart of same combo after break: stop - break<br />(doesn't take into account breaks when patient is on no diabetes meds) | if add>=1 & rem==0 -> add<br />if add==0 & rem>=1 -> remove<br />if add>=1 & rem>=1 -> swap<br />if add==0 & rem==0 & drugcomboorder==1 -> start of px<br />if add==0 & rem==0 & drugcomboorder!=1 -> stop - break |
| nextdrugchange | what change from present drug combo to next one represents: add / remove / swap / (no next combo as this is the) end of px / restart of same combo after break: stop - break<br />(doesn't take into account breaks when patient is on no diabetes meds) | if nextadd>=1 & nextrem==0 -> add<br />if nextadd==0 & nextrem>=1 -> remove<br />if nextadd>=1 & nextrem>=1 -> swap<br />if nextadd==0 & nextrem==0 & nextdcdate!=dcstopdate -> stop - break<br />if nextadd==0 & nextrem==0 & nextdcdate==dcstopdate -> stop - end of px |
| timetochange | time until changed to different drug combo in days (**does** take into account breaks when patient is on no diabetes meds) | if last combination before end of prescriptions, or if next event is a break from all drug classes, use dcstopdate to calculate |
| timetoaddrem | time until another drug class added or removed in days | NA if last combination before end of prescriptions |
| timeprevcombo | time since started previous drug combo in days | NA if no previous combo - i.e. at start of prescriptions<br />does not take into account breaks (i.e. if patient stops all drug classes) |
| multi_drug_start | whether multiple drug classes started on this dcstartdate | If add>1, multi_drug_start= 1 (yes), otherwise multi_drug_start=0 (no) |

&nbsp;

## Script: 02_mm_baseline_biomarkers
### Table: mm_baseline_biomarkers

Biomarkers included currently: weight, height, bmi, fastingglucose, hdl, triglyceride, blood creatinine, ldl, alt, ast, totalcholesterol, dbp, sbp, acr, hba1c, egfr (from blood creatinine), blood albumin, bilirubin, haematocrit, haemoglobin, PCR, urine albumin, urine creatinine (latter two not included but separately but combined where on the same day to give 'acr_from_separate' values.

NB: BMI and ACR are from BMI and ACR specific codes only, not calculated from weight+height / albumin+creatinine measurements

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| pre{biomarker} | biomarker value at baseline | For all biomarkers except HbA1c: pre{biomarker} is closest biomarker to dstartdate within window of -730 days (2 years before dstartdate) and +7 days (a week after dstartdate)<br /><br />For HbA1c: prehba1c is closest HbA1c to dstartdate within window of -183 days (6 months before dstartdate) and +7 days (a week after dstartdate). HbA1c before timeprevcombo excluded |
| pre{biomarker}date | date of baseline biomarker | |
| pre{biomarker}drugdiff | days between dstartdate and baseline biomarker (negative: biomarker measured before drug start date) | |
| height | height in cm | Mean of all values on/post- drug start date |

&nbsp;

## Script: 03_mm_biomarker_response
### Table: mm_biomarker_response

Biomarkers included currently: weight, bmi, fastingglucose, hdl, triglyceride, blood creatinine, ldl, alt, ast, totalcholesterol, dbp, sbp, acr, hba1c, egfr (from blood creatinine), blood albumin, bilirubin, haematocrit, haemoglobin, PCR, acr_from_separate as above (02_mm_baseline_biomarkers).

NB: BMI and ACR are from BMI and ACR specific codes only, not calculated from weight+height / albumin+creatinine measurements

1 line per patid / drug class instance (continuous period of drug class use) for all patids. Only uses first instance of use of that drug class.

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| post{biomarker}6m | biomarker value at 6m post drug initiation | post{biomarker}6m: closest biomarker to dstartdate+183 days (6 months), at least 3 months (91 days) after dstartdate, before 9 months, before timetoremadd (another drug class add or removed), and before timetochange+91 days (for most drug periods, timetoremadd=timetochange, they are only different if before a break, in which case timetochange<timetoremadd as timetochange doesn't include period of break and timetoremadd does - so biomarker can be within break period, up to 91 days after stopping drug of interest).<br /><br />No posthba1c6m value where changed diabetes meds <= 61 days before drug start (timeprevcombo<=61) |
| post{biomarker}6mdate | date of biomarker at 6m post drug initiation | |
| post{biomarker}6mdrugdiff | days between dstartdate and post{biomarker}6mdate | |
| post{biomarker}12m | biomarker value at 12m post drug initiation | posthba1c12m: closest biomarker to dstartdate+365 days (12 months), at least 9 months (274 days) after dstartdate, before 15 months, before timetoremadd (another drug class add or removed), and before timetochange+91 days (for most drug periods, timetoremadd=timetochange, they are only different if before a break, in which case timetochange<timetoremadd as timetochange doesn't include period of break and timetoremadd does - so biomarker can be within break period, up to 91 days after stopping drug of interest).<br /><br />No posthba1c12m value where changed diabetes meds <= 61 days before drug start (timeprevcombo<=61) |
| post{biomarker}12mdate | date of biomarker at 12m post drug initiation | |
| post{biomarker}12mdrugdiff | days between dstartdate and post{biomarker}6mdate | |
| {biomarker}resp6m | post{biomarker}6m - pre{biomarker} | |
| {biomarker}resp12m | post{biomarker}12m - pre{biomarker} | |
| next_egfr_date | date of first eGFR post-baseline | |
| egfr_40_decline_date | date at which eGFR<=40% of baseline value | |

&nbsp;

## Script: 04_mm_comorbidities
### Table: mm_comorbidities

Comorbidities included currently: af, angina, asthma, bronchiectasis, ckd5_code, cld, copd, cysticfibrosis, dementia, diabeticnephropathy, fh_premature_cvd, haem_cancer, heartfailure, hypertension (uses primary care data only, see note in script), ihd, myocardialinfarction, neuropathy, otherneuroconditions, pad, pulmonaryfibrosis, pulmonaryhypertension, retinopathy, revasc, rheumatoidarthritis, solid_cancer, solidorgantransplant, stroke, tia, primary_hhf (hospitalisation for HF with HF as primary cause), anxiety_disorders, medspecific_gi (from genital_infection codelist), unspecific_gi (from genital_infection_nonspec medcodelist and definite_genital_infection_meds prodcodelist), benignprostatehyperplasia, micturition_control, volume_depletion, urinary_frequency, falls, lowerlimbfracture, fluvacc (from fluvacc_stopflu_med and fluvacc_stopflu_prod codelists, courtesy of the STOPflu project), dka (HES only), amputation (from hosp_cause_majoramputation and hosp_cause_minoramputation; both in HES only and not just primary cause), osteoporosis, unstable angina (HES only).

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description |
| --- | --- |
| predrug_{comorbidity} | binary 0/1 if any instance of comorbidity before/at dstartdate |
| predrug_earliest_{comorbidity} | earliest occurrence of comorbidity before/at dstartdate |
| predrug_latest_{comorbidity} | latest occurrence of comorbidity before/at dstartdate |
| postdrug_first_{comorbidity} | earliest occurrence of comorbidity after (not at) dstartdate |
| postdrug_first_{comorbidity}\_gp_only | earliest occurrence of comorbidity after (not at) dstartdate, from GP (primary care) codes only |
| not present for unspecific_gi comorbidity |
| postdrug_first_{comorbidity}\_hes_icd10_only | earliest occurrence of comorbidity after (not at) dstartdate, from HES (secondary care) ICD10 (diagnosis) codes only |
| not present for unspecific_gi comorbidity |
| postdrug_first_{comorbidity}\_hes_opcs4_only | earliest occurrence of comorbidity after (not at) dstartdate, from HES (secondary care) OPCS4 (operation) codes only |
| not present for unspecific_gi comorbidity |
| hosp_admission_prev_year | 1 if patient has 1 or more hospital admision in the previous year to drug start (not including dstartdate).<br />NA if no admissions or if HES data not available - changed to 0 if no admissions and HES data available in final merge script |
| postdrug_first_all_cause_hosp | earliest inpatient hospital admission after (not at) dstartdate - emegency only (excluding admimeth=11, 12, or 13) |

&nbsp;

## Script: 05_mm_ckd_stages
### Table: mm_ckd_stages

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| preckdstage | CKD stage at baseline | CKD stages calculated as per [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#ckd-chronic-kidney-disease-stage)<br />eGFR calculated from creatinine using CKD-EPI creatinine 2021 equation<br />Start date = earliest test for CKD stage, only including those confirmed by another test at least 91 days later, without a test for a different stage in the intervening period<br />Baseline stage = maximum stage with start date < dstartdate or up to 7 days afterwards<br />CKD5 supplemented by medcodes/ICD10/OPCS4 codes for CKD5 / ESRD |
| preckdstagedate | date of onset of baseline CKD stage (earliest test for this stage) | |
| preckdstagedrugdiff | days between dstartdate and preckdstagedate | |
| postckdstage5date | date of onset of CKD stage 5 if occurs post-drug start (more than 7 days after drug start as baseline goes up to 7 days after drug start) | |
| postckdstage345date | date of onset of CKD stage 3a-5 if occurs post-drug start (more than 7 days after drug start as baseline goes up to 7 days after drug start) | |

&nbsp;

## Script: 06_mm_non_diabetes_meds
### Table: mm_non_diabetes_meds

Medications included currently:ACE-inhibitors, beta-blockers, calcium-channel blockers, thiazide-like diuretics (all BP meds), loop diuretics, potassium-sparing duiretics, definite genital infection meds (used in unspecific_gi comorbiditiy - see comorbidity script and table), prodspecific_gi (from topical candidal meds codelist), immunosuppressants, oral steriods, oestrogens, statins, fluvacc_stopflu_prod (used in combination with medcodes - see comorbidities script and table).

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description |
| --- | --- |
| predrug_earliest_{med} | earliest script for non-diabetes medication before/at dstartdate |
| predrug_latest_{med} | latest script for non-diabetes medication before/at dstartdate |
| postdrug_first_{med} | earliest script for non-diabetes medication after (not at) dstartdate |

&nbsp;

## Script: 07_mm_smoking
### Table: mm_smoking

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| smoking_cat | Smoking category at drug start: Non-smoker, Ex-smoker or Active smoker | Derived from [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#smoking) |
| qrisk2_smoking_cat | QRISK2 smoking category code (0-4) | |
| qrisk2_smoking_cat_uncoded | Decoded version of qrisk2_smoking_cat: 0=Non-smoker, 1= Ex-smoker, 2=Light smoker, 3=Moderate smoker, 4=Heavy smoker | |

&nbsp;

## Script: 08_mm_discontinuation
### Table: mm_discontinuation

1 line per patid / drug class instance (continuous period of drug class use) for all patids

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| ttc3m | 1 if timeondrug<=3 months | |
| ttc6m | 1 if timeondrug<=6 months (may also be <=3 months) | |
| ttc12m | 1 if timeondrug<=12 months (may also be <=6 months/3 months) | |
| stopdrug3m_3mFU | 1 if discontinue within 3 months and have at least 3 months followup to confirm this<br />0 if don't discontinue at 3 months | Followup time is time between last prescription of any glucose lowering medication and last prescription of this particular drug (the one they are discontinuing)<br /><br />These variables are missing if either a) the person does discontinue in the time period stated, but there is another glucose-lowering medication added or removed before this discontinuation, OR b) the person does discontinue in the time period stated, but the discontinuation represents a break int he current medication before restarting, OR c) the person does discontinue in the time stated, but does not have the followup time stated to confirm this |
| stopdrug3m_6mFU | 1 if discontinue within 3 months and have at least 6 months followup to confirm this<br />0 if don't discontinue at 3 months | |
| stopdrug6m_3mFU | 1 if discontinue within 6 months and have at least 3 months followup to confirm this<br />0 if don't discontinue at 6 months | |
| stopdrug6m_6mFU | 1 if discontinue within 6 months and have at least 6 months followup to confirm this<br />0 if don't discontinue at 6 months | |
| stopdrug12m_3mFU | 1 if discontinue within 12 months and have at least 3 months followup to confirm this<br />0 if don't discontinue at 12 months | |
| stopdrug12m_6mFU | 1 if discontinue within 12 months and have at least 6 months followup to confirm this<br />0 if don't discontinue at 12 months | |

&nbsp;

## Script: 09_mm_death_cause
### Table: mm_death_cause

1 line per patid for all patids in ONS death table

| Variable name | Description |
| --- | --- |
| primary_death_cause | primary death cause from ONS data (ICD10; 'cause' in ONS death table) |
| secondary_death_cause1-15 | secondary death cases from ONS data (ICD10; 'cause1'-'cause15' in ONS death table) |
| cv_death_primary | 1 if primary cause of death is CV |
| cv_death_any | 1 if any (primary or secondary) cause of death is CV |
| hf_death_primary | 1 if primary cause of death is heart failure |
| hf_death_any | 1 if any (primary or secondary) cause of death is heartfailure |

&nbsp;

## Script: 10_mm_final_merge
### Table: mm_{today's date}\_t2d_1stinstance

1 line per patid / drug class instance (continuous period of drug class use), but first instance (druginstance==1) drug periods only, and excludes those starting within 91 days of registration

Only includes patids with Type 2 diabetes in Type 1/2 cohort and with HES linkage (with_hes==1; see below all_t1t2_cohort table)

Adds in variables from other scripts (e.g. comorbidities, non-diabetes meds), and adds some additional ones (below)

| Variable name | Description |
| --- | --- |
| dstartdate_age | age at dstartdate in years (dstartdate-dob) |
| dstartdate_dm_dur_all | diabetes duration at dstartdate in years (dstartdate-dm_diag_date_all)<br />No missingness |
| dstartdate_dm_dur | diabetes duration at dstartdate in years (dstartdate-dm_diag_date)<br />Missing if diabetes diagnosis date is <91 days following registration (i.e. dm_diag_flag==1), as final merge script sets dm_diag_date to missing where this is the case - this is the only reason why this variable would be missing |
| qdiabeteshf_5yr_score | 5-year QDiabetes-heart failure score (in %)<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing HbA1c, ethnicity or smoking info)<br />NB: NOT missing if have pre-existing HF but obviously not valid |
| qdiabeteshf_lin_predictor | QDiabetes heart failure linear predictor<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing HbA1c, ethnicity or smoking info)<br />NB: NOT missing if have pre-existing HF but obviously not valid |
| qrisk2_5yr_score | 5-year QRISK2-2017 score (in %)<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing ethnicity or smoking info)<br />NB: NOT missing if have CVD but obviously not valid |
| qrisk2_10yr_score | 10-year QRISK2-2017 score (in %)<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing ethnicity or smoking info)<br />NB: NOT missing if have CVD but obviously not valid |
| qrisk2_lin_predictor | QRISK2-2017 linear predictor<br />NB: NOT missing if have CVD but obviously not valid<br />Missing for anyone with age/BMI/biomarkers outside of range for model (or missing ethnicity or smoking info) |
| ckdpc_egfr60_total_score | CKDPC risk score for 5-year risk of eGFR<=60ml/min/1.73m2 in people with diabetes (total events). <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (ethnicity, eGFR, HbA1c, smoking info, BMI or UACR) |
| ckdpc_egfr60_total_lin_predictor | Linear predictor for CKDPC risk score for eGFR<=60ml/min/1.73m2 in people with diabetes (total events). <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (ethnicity, eGFR, HbA1c, smoking info, BMI or UACR) |
| ckdpc_egfr60_confirmed_score | CKDPC risk score for 5-year risk of eGFR<=60ml/min/1.73m2 in people with diabetes (confirmed events only). <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (ethnicity, eGFR, HbA1c, smoking info, BMI or UACR) |
| ckdpc_egfr60_confirmed_lin_predictor | Linear predictor for CKDPC risk score for eGFR<=60ml/min/1.73m2 in people with diabetes (confirmed events). <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (ethnicity, eGFR, HbA1c, smoking info, BMI or UACR) |
| ckdpc_40egfr_score | CKDPC risk score for 3-year risk of 40% decline in eGFR or kidney failure in people with diabetes and baseline eGFR>=60ml/min/1.73m2. <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 at drug start (but not if missing eGFR), with age/BMI/biomarkers outside of range for model, or missing any predictors (eGFR, HbA1c, smoking info, SBP, BMI or UACR) |
| ckdpc_40egfr_lin_predictor | Linear predictor for CKDPC risk score for 40% decline in eGFR or kidney failure in people with diabetes and baseline eGFR>=60ml/min/1.73m2. <br />Missing for anyone with CKD stage 3a-5 or eGFR<60ml/min/1.73m2 (but not if missing eGFR) at drug start, with age/BMI/biomarkers outside of range for model, or missing any predictors (eGFR, HbA1c, smoking info, SBP, BMI or UACR) |

&nbsp;

## Script: all_patid_ethnicity_table
### Table: all_patid_ethnicity

1 line per patid in download

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| ethnicity_5cat | 5-category ethnicity: (0=White, 1=South Asian, 2=Black, 3=Other, 4=Mixed) | Uses [our algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#ethnicity) (NB: use all medcodes; no date restrictions):<br />Use most frequent category<br />If multiple categories with same frequency, use latest one<br />If multiple categories with same frequency and used as recently as each other, label as missing<br />Use HES if missing/no consensus from medcodes |
| ethnicity_16cat | 16-category ethnicity: (1=White British, 2=White Irish, 3=Other White, 4=White and Black Caribbean, 5=White and Black African, 6=White and Asian, 7=Other Mixed, 8=Indian, 9=Pakistani, 10=Bangladeshi, 11=Other Asian, 12=Caribbean, 13=African, 14=Other Black, 15=Chinese, 16=Other) | |
| ethnicity_qrisk2 | QRISK2 ethnicity category: (1=White, 2=Indian, 3=Pakistani, 4=Bangladeshi, 5=Other Asian, 6=Black Caribbean, 7=Black African, 8=Chinese, 9=Other) | |

&nbsp;

## Script: all_patid_townsend_deprivation_score
### Table: all_patid_townsend

1 line per patid with Index of Multiple Deprivation Score from CPRD

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| imd2015_10 | English Index of Multiple Deprivation (IMD) decile (1=most deprived, 10=least deprived) | |
| tds_2011 | Townsend Deprivation Score (TDS) - made by converting IMD decile scores (median TDS for LSOAs with the same IMD decile as patient used) | See [algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#townsend-deprivation-scores) |

&nbsp;

## Script: all_t1t2_cohort_table
### Table: all_t1t2_cohort

1 line per patid who meet requirements for being in Type 1/2 cohort

| Variable name | Description | Notes on derivation |
| --- | --- | --- |
| gender | gender (1=male, 2=female) | |
| dob | date of birth | if month and date missing, 1st July used, if date but not month missing, 15th of month used, or earliest medcode in year of birth if this is earlier |
| pracid | practice ID | |
| prac_region | practice region: 1=North East, 2=North West, 3=Yorkshire And The Humber, 4=East Midlands, 5=West Midlands, 6=East of England, 7=South West, 8=South Central, 9=London, 10=South East Coast, 11 Northern Ireland, 12 Scotland, 13 Wales | |
| has_insulin | has a prescription for insulin ever (excluding invalid dates - before DOB / after LCD/death/deregistration) | |
| type1_code_count | number of Type 1-specific codes in records (any date) | |
| type2_code_count | number of Type 2-specific codes in records (any date) | |
| dm_diag_dmcodedate | earliest diabetes medcode (including diabetes exclusion codes; excluding those with obstypeid=4 (family history) and invalid dates) | |
| dm_diag_hba1cdate | earliest HbA1c >47.5 mmol/mol (excluding invalid dates, including those with valid value and unit codes only) | |
| dm_diag_ohadate | earliest OHA prescription (excluding invalid dates) | |
| dm_diag_insdate | earliest insulin prescription (excluding invalid dates) | |
| dm_diag_date_all / dm_diag_date | diabetes diagnosis date<br />dm_diag_date_all is not missing for anyone<br />In final merge script, 'dm_diag_date' is the same as 'dm_diag_date_all' except it is set to missing if diabetes diagnosis date is <91 days following registration (i.e. dm_diag_flag==1) - this is the only reason why this variable would be missing | earliest of dm_diag_dmcodedate, dm_diag_hba1cdate, dm_diag_ohadate, and dm_diag_insdate.<br />It's worth noting that we have a number of people classified as Type 2 who appear to have been diagnosed at a young age, which is likely to be a coding error. This small proportion shouldn't affect Mastermind analysis results greatly, but might need to be considered for other analysis |
| dm_diag_codetype | whether diagnosis date represents diabetes medcode (1), high HbA1c (2), OHA prescription (3) or insulin (4) - if multiple on same day, use lowest number | |
| dm_diag_flag | whether diagnosis date is <91 days following registration | |
| dm_diag_age_all / dm_diag_age | age at diabetes diagnosis<br />dm_diag_age_all is not missing for anyone<br />In final merge script, 'dm_diag_age' is the same as 'dm_diag_age_all' except it is set to missing if diabetes diagnosis date is <91 days following registration (i.e. dm_diag_flag==1) - this is the only reason why this variable would be missing | dm_diag_date - dob<br />See above note next to dm_diag_date_all variable on young diagnosis in T2Ds |
| dm_diag_before_reg | whether diagnosed before registration | |
| ins_in_1_year | whether started insulin within 1 year of diagnosis (**0 may mean no or missing**) | |
| current_oha | whether prescription for insulin within last 6 months of data | last 6 months of data = those before LCD/death/deregistration |
| diabetes_type | diabetes type | See [algorithm](https://github.com/Exeter-Diabetes/CPRD-Codelists#diabetes-algorithms)<br />See above note next to dm_diag_date_all variable on young diagnosis in T2Ds |
| regstartdate | registration start date | |
| gp_record_end | earliest of last collection date from practice, deregistration and 31/10/2020 (latest date in records) | |
| death_date | earliest of 'cprddeathdate' (derived by CPRD) and ONS death date | NA if no death date |
| with_hes | 1 for patients with HES linkage and n_patid_hes<=20, otherwise 0<br />In final merge script - usually exclude people where with_hes==0 | |


## Previous MASTERMIND papers (from GOLD dataset)
* [Precision Medicine in Type 2 Diabetes: Clinical Markers of Insulin Resistance Are Associated With Altered Short- and Long-term Glycemic Response to DPP-4 Inhibitor Therapy](https://diabetesjournals.org/care/article/41/4/705/36908/Precision-Medicine-in-Type-2-Diabetes-Clinical) Dennis et al. 2018
* [Sex and BMI Alter the Benefits and Risks of Sulfonylureas and Thiazolidinediones in Type 2 Diabetes: A Framework for Evaluating Stratification Using Routine Clinical and Individual Trial Data](https://diabetesjournals.org/care/article/41/9/1844/40749/Sex-and-BMI-Alter-the-Benefits-and-Risks-of) Dennis et al. 2018
* [Time trends and geographical variation in prescribing of drugs for diabetes in England from 1998 to 2017](https://dom-pubs.onlinelibrary.wiley.com/doi/full/10.1111/dom.13346) Curtis et al. 2018
* [What to do with diabetes therapies when HbA1c lowering is inadequate: add, switch, or continue? A MASTERMIND study](https://bmcmedicine.biomedcentral.com/articles/10.1186/s12916-019-1307-8) McGovern et al. 2019
* [Time trends in prescribing of type 2 diabetes drugs, glycaemic response and risk factors: A retrospective analysis of primary care data, 2010–2017](https://dom-pubs.onlinelibrary.wiley.com/doi/10.1111/dom.13687) Dennis et al. 2019
* [Prior event rate ratio adjustment produced estimates consistent with randomized trial: a diabetes case study](https://www.jclinepi.com/article/S0895-4356(19)30114-3/fulltext) Rodgers et. al 2020
* [Risk factors for genital infections in people initiating SGLT2 inhibitors and their impact on discontinuation](https://drc.bmj.com/content/8/1/e001238.long) McGovern et al. 2020
* [Development of a treatment selection algorithm for SGLT2 and DPP-4 inhibitor therapies in people with type 2 diabetes: a retrospective cohort study](https://www.thelancet.com/journals/landig/article/PIIS2589-7500(22)00174-1/fulltext) Dennis et al. 2022
