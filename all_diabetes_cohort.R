
# Identify those in mixed T1/T2/'Other' (those with codes for other types of diabetes) diabetes cohort as per https://github.com/Exeter-Diabetes/CPRD-Codelists#diabetes-algorithms

# Add useful baseline features including diabetes diagnosis variables (date of diagnosis, type of diabetes for Type 1/Type 2) and ethnicity

# Uses other pre-made tables:
## validDateLookup has min_dob (earliest possible DOB), and gp_end_date (earliest of last collection date from practice, deregistration, cprd_ddate, and 2023-10-20)
## all_patid_ethnicity, from all_patid_ethnicity.R script as per https://github.com/Exeter-Diabetes/CPRD-Codelists#ethnicity


############################################################################################

#Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes_2024 = codesets$getAllCodeSetVersion(v = "01/06/2024")

#Check codelists 
current_list <- codesets$listCodeSets()

############################################################################################

#Data quality check - should only include acceptable' patients (see CPRD data specification for definition)
cprd$tables$patient %>% count() #2727999 - total patient count in download
cprd$tables$patient %>% filter(acceptable ==1) %>% count() #2727999
cprd$tables$patient %>% filter(patienttypeid ==3) %>% count() #2727999
#All are 'acceptable' and have patienttypeid==3 ('Regular')

############################################################################################

##CPRD recommend excluding 44 practices (as below) that appear likely to have merged into other contributing practices (patient data could be duplicated)
##Define patients to remove later

analysis = cprd$analysis("diabetes_cohort")

practice_exclusion_ids <- cprd$tables$patient %>% 
  filter(pracid == "20024" | pracid == "20036" |pracid == "20091" |pracid == "20171" | pracid == "20178" |pracid == "20202" | pracid == "20254" | pracid == "20389" |pracid == "20430" |pracid == "20452" |
           pracid == "20469" | pracid == "20487" | pracid == "20552" | pracid == "20554" | pracid == "20640" | pracid == "20717" | pracid == "20734" | pracid == "20737" | pracid == "20740" | pracid == "20790" |
           pracid == "20803" | pracid == "20822" | pracid == "20868" | pracid == "20912" | pracid == "20996" | pracid == "21001" | pracid == "21015" | pracid == "21078" | pracid == "21112" | pracid == "21118" |
           pracid == "21172" | pracid == "21173" | pracid == "21277" | pracid == "21281" | pracid == "21331" | pracid == "21334" | pracid == "21390" | pracid == "21430" | pracid == "21444" | pracid == "21451" |
           pracid == "21529" | pracid == "21553" | pracid == "21558" | pracid == "21585") %>%
  analysis$cached("practice_exclusion_ids")

practice_exclusion_ids %>% count() #30759


############################################################################################

##Define patients with gender=3 (indeterminate) to remove later

gender_exclusion_ids <- cprd$tables$patient %>% 
  filter(gender==3) %>%
  analysis$cached("gender_exclusion_ids")

gender_exclusion_ids %>% count() #43

cprd$tables$patient %>% anti_join(practice_exclusion_ids, by="patid") %>% anti_join(gender_exclusion_ids, by="patid") %>% count() #2697197


############################################################################################

# Define diabetes cohort (has diabetes QOF code with valid date)
## QOF codelist uses Read codes from version 38 (contains all codes in previous versions and was last Read version published)
# SNOMED codes uses v44 plus extra codes from v46/47 (they are identical to each other; 6 codes added) and extra codes from v48 (9 more not in v46/47)
# Includes QOF codes for non-T1/T2 types of diabetes (NB: no gestational diabetes QOF codes)

analysis = cprd$analysis("all_patid")

raw_qof_diabetes_medcodes <- cprd$tables$observation %>%
  inner_join(codes_2024$qof_diabetes, by="medcodeid") %>%
  analysis$cached("raw_qof_diabetes_medcodes", indexes=c("patid", "obsdate", "qof_diabetes_cat"))

analysis = cprd$analysis("diabetes_cohort")

qof_ids <- raw_qof_diabetes_medcodes %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_end_date) %>%
  distinct(patid) %>%
  analysis$cached("qof_ids", unique_indexes="patid")

qof_ids %>% count() #2137263

qof_ids %>% anti_join(practice_exclusion_ids, by="patid") %>% anti_join(gender_exclusion_ids, by="patid") %>% count() #2110415


############################################################################################

# Exclude diabetes insipidus or gestational diabetes ever

analysis = cprd$analysis("all_patid")

raw_diabetes_insipidus_medcodes <- cprd$tables$observation %>%
  inner_join(codes_2024$diabetes_insipidus, by="medcodeid") %>%
  analysis$cached("raw_diabetes_insipidus_medcodes", indexes=c("patid", "obsdate"))

analysis = cprd$analysis("diabetes_cohort")

insipidus_ids <- raw_diabetes_insipidus_medcodes %>%
  distinct(patid) %>%
  analysis$cached("insipidus_ids", unique_indexes="patid") 

insipidus_ids %>% count() #1800

qof_ids %>% anti_join(practice_exclusion_ids, by="patid") %>% anti_join(gender_exclusion_ids, by="patid") %>% inner_join(insipidus_ids, by="patid") %>% count() #1300


gestational_ids <- raw_diabetes_medcodes %>%
  filter(all_diabetes_cat=="gestational" | all_diabetes_cat == "gestational history") %>%
  distinct(patid) %>%
  analysis$cached("gestational_ids", unique_indexes="patid")

gestational_ids %>% count() #145147

qof_ids %>% anti_join(practice_exclusion_ids, by="patid") %>% anti_join(gender_exclusion_ids, by="patid") %>% inner_join(gestational_ids, by="patid") %>% count() #28053


#Combine all of above
diabetes_cohort_ids <- qof_ids %>%
  anti_join(practice_exclusion_ids, by="patid") %>%
  anti_join(gender_exclusion_ids, by="patid") %>%
  anti_join(insipidus_ids, by="patid") %>%
  anti_join(gestational_ids, by="patid") %>%
  analysis$cached("ids", unique_indexes="patid")

diabetes_cohort_ids %>% count() #2081081


############################################################################################

# Diagnosis dates

# Earliest of: any diabetes medcode (excluding obstype==4 [family history]), HbA1c >=47.5mmol/mol, OHA script, insulin script (all - valid dates only)

## If Type 2 (determined later in this script), ignore any diabetes medcodes in year of birth - use next code/HbA1c/script
## If Type 2 and have high HbA1c or OHA/insulin script in year of birth, will exclude later
## Similarly, if Type 2 and ONLY have diabetes medcodes in year of birth (and no high HbA1cs or OHA/insulin scripts later), will exclude later

## All diabetes medcodes, OHA scripts and insulin scripts also needed for defining diabetes type - so cache these
## Have also cached HbA1c as needed for later analysis

analysis = cprd$analysis("all_patid")


## All diabetes medcodes (need for diagnosis date (cleaned) and for defining Type 1 vs Type 2 (raw))
raw_diabetes_medcodes <- cprd$tables$observation %>%
  inner_join(codes_2024$all_diabetes, by="medcodeid") %>%
  analysis$cached("raw_diabetes_medcodes", indexes=c("patid", "obsdate", "all_diabetes_cat"))


## All HbA1cs
### Remove if <1990 and assume in % and convert to mmol/mol if <=20 (https://github.com/Exeter-Diabetes/CPRD-Codelists#hba1c)
raw_hba1c <- cprd$tables$observation %>%
  inner_join(codes_2024$hba1c, by="medcodeid") %>%
  analysis$cached("raw_hba1c_medcodes", indexes=c("patid", "obsdate", "testvalue", "numunitid"))

clean_hba1c <- raw_hba1c %>%
  filter(year(obsdate)>=1990) %>%
  mutate(testvalue=ifelse(testvalue<=20, ((testvalue-2.152)/0.09148), testvalue)) %>%
  clean_biomarker_values(testvalue, "hba1c") %>%
  clean_biomarker_units(numunitid, "hba1c") %>%
  group_by(patid, obsdate) %>%
  summarise(testvalue=mean(testvalue, na.rm=TRUE)) %>%
  ungroup() %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_end_date) %>%
  select(patid, date=obsdate, testvalue) %>%
  analysis$cached("clean_hba1c_medcodes", indexes=c("patid", "date", "testvalue"))


## All OHA scripts (need for diagnosis date (cleaned) and definition (cleaned))
raw_oha <- cprd$tables$drugIssue %>%
  inner_join(cprd$tables$ohaLookup, by="prodcodeid") %>%
  analysis$cached("raw_oha_prodcodes", indexes=c("patid", "issuedate"))

clean_oha <- raw_oha %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(issuedate>=min_dob & issuedate<=gp_end_date) %>%
  select(patid, date=issuedate, dosageid, quantity, quantunitid, duration, drug_class_1, drug_class_2, drug_substance_1, drug_substance_2) %>%
  analysis$cached("clean_oha_prodcodes", indexes=c("patid", "date", "drug_class_1", "drug_class_2", "drug_substance_1", "drug_substance_2"))


## All insulin scripts (need for diagnosis date (cleaned) and definition (cleaned))
raw_insulin <- cprd$tables$drugIssue %>%
  inner_join(codes_2024$insulin, by="prodcodeid") %>%
  analysis$cached("raw_insulin_prodcodes", indexes=c("patid", "issuedate"))

clean_insulin <- raw_insulin %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(issuedate>=min_dob & issuedate<=gp_end_date) %>%
  select(patid, date=issuedate, dosageid, quantity, quantunitid, duration, insulin_cat) %>%
  analysis$cached("clean_insulin_prodcodes", indexes=c("patid", "date", "insulin_cat"))


# Cleaning required for diagnosis dates
## If construct query this way (finding earliest date from each of the diagnosis codes, HbA1cs and prescriptions, and then combining, rather than combining all dates and then finding earliest date, doesn't give error about disk space)

analysis = cprd$analysis("diabetes_cohort")

## Earliest clean (i.e. with valid date) non-family history diabetes medcode, excluding diabetes in pregnancy
first_diagnosis_dm_code <- raw_diabetes_medcodes %>%
  filter(all_diabetes_cat != "pregnancy") %>%
  select(patid, obsdate, obstypeid) %>%
  filter(obstypeid!=4) %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_end_date) %>%
  group_by(patid) %>%
  summarise(dm_diag_dmcodedate=min(obsdate, na.rm=TRUE)) %>%
  analysis$cached("first_diagnosis_dm_code", unique_index="patid")

## Earliest clean (i.e. with valid date) non-family history diabetes medcode, excluding diabetes in pregnancy, excluding those in year of birth
first_diagnosis_dm_code_post_yob <- raw_diabetes_medcodes %>%
  filter(all_diabetes_cat != "pregnancy") %>%
  select(patid, obsdate, obstypeid) %>%
  filter(obstypeid!=4) %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(year(obsdate)>year(min_dob) & obsdate<=gp_end_date) %>%
  group_by(patid) %>%
  summarise(dm_diag_dmcodedate_post_yob=min(obsdate, na.rm=TRUE)) %>%
  analysis$cached("first_diagnosis_dm_code_post_yob", unique_index="patid")

## Earliest (clean) HbA1c >=48 mmol/mol
first_high_hba1c <- clean_hba1c %>%
  filter(testvalue>47.5) %>%
  group_by(patid) %>%
  summarise(dm_diag_hba1cdate=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_high_hba1c", unique_index="patid")


## Earliest (clean) OHA script
first_oha <- clean_oha %>%
  group_by(patid) %>%
  summarise(dm_diag_ohadate=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_oha", unique_index="patid")


## Earliest (clean) insulin script
first_insulin <- clean_insulin %>%
  group_by(patid) %>%
  summarise(dm_diag_insdate=min(date, na.rm=TRUE)) %>%
  analysis$cached("first_insulin", unique_index="patid")


# Calculate possible diagnosis dates (overall earliest of code/HbA1c/script, and earliest excluding codes in year of birth)
dm_diag_dates <- diabetes_cohort_ids %>%
  left_join(first_diagnosis_dm_code, by="patid") %>%
  left_join(first_diagnosis_dm_code_post_yob, by="patid") %>%
  left_join(first_high_hba1c, by="patid") %>%
  left_join(first_oha, by="patid") %>%
  left_join(first_insulin, by="patid") %>%
  
  mutate(dm_diag_date_all = pmin(ifelse(is.na(dm_diag_dmcodedate), as.Date("2050-01-01"), dm_diag_dmcodedate),
                                 ifelse(is.na(dm_diag_hba1cdate), as.Date("2050-01-01"), dm_diag_hba1cdate),
                                 ifelse(is.na(dm_diag_ohadate), as.Date("2050-01-01"), dm_diag_ohadate),
                                 ifelse(is.na(dm_diag_insdate), as.Date("2050-01-01"), dm_diag_insdate), na.rm=TRUE),
         
         dm_diag_date_all_post_yob = pmin(ifelse(is.na(dm_diag_dmcodedate_post_yob), as.Date("2050-01-01"), dm_diag_dmcodedate_post_yob),
                                          ifelse(is.na(dm_diag_hba1cdate), as.Date("2050-01-01"), dm_diag_hba1cdate),
                                          ifelse(is.na(dm_diag_ohadate), as.Date("2050-01-01"), dm_diag_ohadate),
                                          ifelse(is.na(dm_diag_insdate), as.Date("2050-01-01"), dm_diag_insdate), na.rm=TRUE)) %>%
  
  analysis$cached("dm_diag_dates", unique_indexes="patid", indexes=c("dm_diag_date_all", "dm_diag_date_all_post_yob"))


############################################################################################

# Define diabetes type: type 1 or type 2 or other

## If they have a non-T1/non-T2 code, define as 'other'

non_T1T2_ids <- raw_diabetes_medcodes %>%
  filter(all_diabetes_cat=="insulin receptor abs" |
           all_diabetes_cat=="malnutrition" |
           all_diabetes_cat=="mody" |
           all_diabetes_cat=="other type not specified" |
           all_diabetes_cat=="other/unspec genetic inc syndromic" |
           all_diabetes_cat=="secondary") %>%
  distinct(patid) %>%
  analysis$cached("non_T1T2_ids", unique_indexes="patid")

non_T1T2_ids %>% count() #14505

non_T1T2_ids <- non_T1T2_ids %>% mutate(diabetes_type="other",
                                        diabetes_type_post_yob="other")



## Make tables for variables required for Type 1 vs 2 definition (do for everyone)

### Whether or not have valid insulin prescription
has_insulin <- clean_insulin %>%
  select(patid) %>%
  distinct() %>%
  mutate(has_insulin=1L) %>%
  analysis$cached("has_insulin", unique_indexes="patid")


### Type 1-specific code count (any date)
type1_code_count <- raw_diabetes_medcodes %>%
  filter(all_diabetes_cat=="Type 1") %>%
  group_by(patid) %>%
  summarise(type1_code_count=n()) %>%
  analysis$cached("type1_code_count", unique_indexes="patid")


### Type 2-specific code count (any date)
type2_code_count <- raw_diabetes_medcodes %>%
  filter(all_diabetes_cat=="Type 2") %>%
  group_by(patid) %>%
  summarise(type2_code_count=n()) %>%
  analysis$cached("type2_code_count", unique_indexes="patid")


### Age of diagnosis
#### First need to estimate DOB: earliest of any medcode in Observation table (besides those before mob/yob), or use the 15/mob/yob if mob where provided, or 30/06/yob if only yob provided

dob <- cprd$tables$observation %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob) %>%
  group_by(patid) %>%
  summarise(earliest_medcode=min(obsdate, na.rm=TRUE)) %>%
  ungroup() %>%
  analysis$cached("earliest_medcode", unique_indexes="patid")

#### Check count
dob %>% count() #2727999 - everyone in download

#### No-one has missing dob or earliest_medcode so pmin (runs as 'LEAST' in MySQL) works
dob <- dob %>%
  inner_join(cprd$tables$patient, by="patid") %>%
  mutate(dob=as.Date(ifelse(is.na(mob), paste0(yob,"-06-30"), paste0(yob, "-",mob,"-15")))) %>%
  inner_join(cprd$tables$validDateLookup, by = "patid") %>%
  mutate(dob=pmin(dob, earliest_medcode, na.rm=TRUE)) %>%
  mutate(dob=ifelse(regstartdate>=min_dob & regstartdate<dob, regstartdate, dob)) %>%
  select(patid, dob = dob, mob, yob, regstartdate) %>%
  analysis$cached("dob", unique_indexes="patid")


#### Calculate diagnosis age from dob and diagnosis date
#### Also add in whether diagnosis date < regstartdate as will need this for time to insulin
dm_diag_age <- dm_diag_dates %>%
  left_join(dob, by="patid") %>%
  mutate(dm_diag_age_all=(datediff(dm_diag_date_all, dob))/365.25,
         dm_diag_age_all_post_yob=(datediff(dm_diag_date_all_post_yob, dob))/365.25,
         dm_diag_before_reg=dm_diag_date_all<regstartdate,
         dm_diag_before_reg_post_yob=dm_diag_date_all_post_yob<regstartdate) %>%
  select(patid, dob, mob, yob, regstartdate, starts_with("dm_diag")) %>%
  analysis$cached("dm_diag_age", unique_indexes="patid", indexes=c("dm_diag_date_all", "dm_diag_age_all"))


### Whether first insulin script within 1 year of diagnosis
#### Included even if prescription is before registration start
time_to_insulin <- clean_insulin %>%
  group_by(patid) %>%
  summarise(first_insulin=min(date, na.rm=TRUE)) %>%
  ungroup() %>%
  inner_join(dm_diag_dates, by="patid") %>%
  mutate(ins_in_1_year=ifelse(datediff(first_insulin, dm_diag_date_all)/365.25<=1, 1L, NA),
         ins_in_1_year_post_yob=ifelse(datediff(first_insulin, dm_diag_date_all_post_yob)/365.25<=1, 1L, NA)) %>%
  select(patid, ins_in_1_year, ins_in_1_year_post_yob) %>%
  analysis$cached("time_to_insulin", unique_indexes="patid")


### Current OHA status (whether have prescription for OHA in last 6 months of records)
current_oha <- clean_oha %>%
  group_by(patid) %>%
  summarise(latest_oha=max(date, na.rm=TRUE)) %>%
  ungroup() %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter((datediff(gp_end_date, latest_oha))/365.25<=0.5) %>%
  mutate(current_oha=1L) %>%
  select(patid, current_oha) %>%
  analysis$cached("current_oha", unique_indexes="patid")


# Calculate diabetes type when include and exclude diabetes medcodes in year of birth (yob)

diabetes_type_prelim <- diabetes_cohort_ids %>%
  left_join(non_T1T2_ids, by="patid") %>%
  left_join(has_insulin, by="patid") %>%
  left_join(type1_code_count, by="patid") %>%
  left_join(type2_code_count, by="patid") %>%
  inner_join(dm_diag_age, by="patid") %>%
  left_join(time_to_insulin, by="patid") %>%
  left_join(current_oha, by="patid") %>%
  replace_na(list(has_insulin=0L, type1_code_count=0L, type2_code_count=0L, ins_in_1_year=0L, ins_in_1_year_post_yob=0L, current_oha=0L)) %>%
  mutate(diabetes_type=ifelse(
    is.na(diabetes_type) &
      ((has_insulin==1 & type1_code_count!=0 & type2_code_count!=0 & type1_code_count>=(2*type2_code_count)) |
         (has_insulin==1 & type1_code_count!=0 & type2_code_count==0) |
         (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all<35 & ins_in_1_year==1) |
         (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all<35 & dm_diag_before_reg==1 & current_oha==0)), "type 1",
    ifelse(is.na(diabetes_type), "type 2", diabetes_type)),
    
    diabetes_type_post_yob=ifelse(
      is.na(diabetes_type_post_yob) &
        ((has_insulin==1 & type1_code_count!=0 & type2_code_count!=0 & type1_code_count>=(2*type2_code_count)) |
           (has_insulin==1 & type1_code_count!=0 & type2_code_count==0) |
           (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all_post_yob<35 & ins_in_1_year_post_yob==1) |
           (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all_post_yob<35 & dm_diag_before_reg_post_yob==1 & current_oha==0)), "type 1",
      ifelse(is.na(diabetes_type_post_yob), "type 2", diabetes_type_post_yob))) %>%
  
  analysis$cached("diabetes_type_prelim", unique_indexes="patid")


############################################################################################

##Checks
# Check those that have a different type of diabetes depending on whether include medcodes in year of birth or not
check <- collect(diabetes_type_prelim %>%
                   filter(diabetes_type!=diabetes_type_post_yob))
## 21 people: 20 are Type 1 if include codes in year of birth, and Type 2 otherwise, 1 is Type 2 if include codes in year of birth, and Type 1 otherwise as affects time to insulin
## These people are 'unclassifiable' - exclude

# Check those with T2D who still have diagnosis date in year of birth due to having script or high HbA1c in year of birth
check <- collect(diabetes_type_prelim %>%
                   filter(diabetes_type=="type 2" & diabetes_type_post_yob=="type 2" & year(dm_diag_date_all_post_yob)==yob))
## 15 people: 13 with OHA in yob, 2 with high HbA1c
## Exclude these people

# Check those with T2D who only have diabetes medcodes in year of birth and no later codes/HbA1cs/scripts
check <- collect(diabetes_type_prelim %>%
                   filter(diabetes_type=="type 2" & diabetes_type_post_yob=="type 2" & is.na(dm_diag_date_all_post_yob)))
# 0 people


# Finalise diabetes type and date of diagnosis - recode dm_diag_dmcodedate, dm_diag_date_all, dm_diag_age_all, dm_diag_before_reg and ins_in_1_year so include/exclude diabetes medcodes in year of birth depending on diabetes type

diabetes_type_final <- diabetes_type_prelim %>%
  
  filter(!((diabetes_type=="type 2" & diabetes_type_post_yob=="type 2" & year(dm_diag_date_all_post_yob)==yob) | (diabetes_type!=diabetes_type_post_yob))) %>%
  
  mutate(raw_dm_diag_dmcodedate=dm_diag_dmcodedate,
         raw_dm_diag_date_all=dm_diag_date_all,
         
         dm_diag_dmcodedate=ifelse(diabetes_type=="type 2", dm_diag_dmcodedate_post_yob, dm_diag_dmcodedate),
         
         dm_diag_date_all=ifelse(diabetes_type=="type 2", dm_diag_date_all_post_yob, dm_diag_date_all),
         
         dm_diag_age_all=ifelse(diabetes_type=="type 2", dm_diag_age_all_post_yob, dm_diag_age_all),
         
         dm_diag_before_reg=ifelse(diabetes_type=="type 2", dm_diag_before_reg_post_yob, dm_diag_before_reg),
         
         ins_in_1_year=ifelse(diabetes_type=="type 2", ins_in_1_year_post_yob, ins_in_1_year)) %>%
  
  select(-c(ends_with("post_yob"))) %>%
  
  analysis$cached("diabetes_type_final", unique_indexes="patid")


############################################################################################

# Remove unreliable diagnosis dates, add in other variables, and cache
## Set diagnosis date to missing if between -30 and +90 days (inclusive) of registration start
## Add dm_diag_date and dm_diag_age - missing if diagnosis date is before registration
## Add variable for what type of code diagnosis is based on
## Also add in gender, registration end, practice ID, and cprd_ddate from patient table
## Also add in last collection date for practice, and derive/keep: regstartdate, gp_record_end (earliest of last collection date from practice and deregistration - will have one or other; NB: this is identical to gp_end_date in validDateLookup), death_date (earliest of 'cprddeathdate' (derived by CPRD))

## Also add in ethnicity from all_patid_ethnicity table from all_patid_ethnicity.R script as per https://github.com/Exeter-Diabetes/CPRD-Codelists#ethnicity

analysis = cprd$analysis("all_patid")

ethnicity <- ethnicity %>% analysis$cached("ethnicity")

#Don't have linkage data yet - can't add with HES, ONS death dates, or IMD scores

analysis = cprd$analysis("all")

diabetes_cohort <- diabetes_type_final %>%
  mutate(dm_diag_date_all=if_else(datediff(dm_diag_date_all, regstartdate)>=-30 & datediff(dm_diag_date_all, regstartdate)<=90, as.Date(NA), dm_diag_date_all),
         
         dm_diag_date=if_else(dm_diag_date_all<regstartdate, as.Date(NA), dm_diag_date_all),
         
         dm_diag_age=ifelse(dm_diag_date_all<regstartdate, NA, dm_diag_age_all),
         
         dm_diag_codetype = ifelse(is.na(dm_diag_date_all), NA,
                                   ifelse(!is.na(dm_diag_dmcodedate) & dm_diag_dmcodedate==dm_diag_date_all, 1L,
                                          ifelse(!is.na(dm_diag_hba1cdate) & dm_diag_hba1cdate==dm_diag_date_all, 2L,
                                                 ifelse(!is.na(dm_diag_ohadate) & dm_diag_ohadate==dm_diag_date_all, 3L, 4L))))) %>%
  
  left_join((cprd$tables$patient %>% select(patid, gender, regenddate, pracid, cprd_ddate)), by="patid") %>%
  left_join((cprd$tables$practice %>% select(pracid, lcd, region)), by="pracid") %>%
  
  mutate(gp_record_end=pmin(if_else(is.na(lcd), as.Date("2050-01-01"), lcd),
                            if_else(is.na(regenddate), as.Date("2050-01-01"), regenddate), na.rm=TRUE),
         
         death_date= cprd_ddate) %>% #don't have ONS data so death date is from cprd only
  
  left_join(ethnicity, by="patid") %>%
  
  select(patid, gender, dob, pracid, prac_region=region, ethnicity_5cat, ethnicity_16cat, ethnicity_qrisk2, has_insulin, type1_code_count, type2_code_count, raw_dm_diag_dmcodedate, raw_dm_diag_date_all, dm_diag_dmcodedate, dm_diag_hba1cdate, dm_diag_ohadate, dm_diag_insdate, dm_diag_date_all, dm_diag_date, dm_diag_codetype, dm_diag_age_all, dm_diag_age, dm_diag_before_reg, ins_in_1_year, current_oha, diabetes_type, regstartdate, gp_record_end, death_date) %>%
  
  analysis$cached("diabetes_cohort", unique_indexes="patid", indexes=c("gender", "dob", "dm_diag_date_all", "dm_diag_date", "dm_diag_age_all", "dm_diag_age", "diabetes_type"))


diabetes_cohort %>% count() # 2081045
diabetes_cohort %>% filter(diabetes_type == "type 2") %>% count() # 1916916
diabetes_cohort %>% filter(diabetes_type == "type 1") %>% count() # 153212
diabetes_cohort %>% filter(diabetes_type == "other") %>% count() # 10917
