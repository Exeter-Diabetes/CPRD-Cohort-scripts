
# Define cohort of individuals who have gestational diabetes

# Find diagnosis date of gestational diabetes and later diabetes if they experience this

# These people excluded from T1T2 cohort as have gestational diabetes codes (counts as an 'exclusion' code)


################################################################################################################################

##################### SETUP ####################################################################################################

library(aurum)
library(tidyverse)

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("all")


################################################################################################################################

##################### GESTATIONAL COHORT DEFINITION ############################################################################


# Define gestational diabetes cohort (acceptable==1, has a gestational diabetes code with a valid date, has no other exclusion type codes)
## NB: gestational diabetes is not in QOF

## Start by caching all gestational diabetes code occurrences

raw_gest <- cprd$tables$observation %>%
  inner_join(codes$gestational_diabetes) %>%
  analysis$cached("raw_gestational_diabetes_medcodes", indexes=c("patid", "obsdate"))


## Find IDs and define earliest and latest gestational diabetes codes

analysis = cprd$analysis("gdm_nov22")

acceptable_patids <- cprd$tables$patient %>%
  filter(acceptable==1) %>%
  inner_join(raw_gest) %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  group_by(patid) %>%
  summarise(earliest_gdm_code=min(obsdate, na.rm=TRUE),
            latest_gdm_code=max(obsdate, na.rm=TRUE)) %>%
  analysis$cached("", unique_indexes="patid")


################################################################################################################################

##################### Type 1 or 2 before GDM? ##########################################################################################


# Earliest of: diabetes medcode (excluding obstype==4 (family history)), HbA1c >=48mmol/mol, OHA script, insulin script (all - valid dates only)


# Cache data - TAKES A LONG TIME
## All diabetes medcodes, OHA scripts and insulin scripts also needed for defining diabetes type - so cache these
## Have also cached HbA1c as needed for later analysis
## Haven't filtered on patids in T1T2 cohort as doesn't make much difference to numbers
## Clean tables now called 'all_patid..."


## All diabetes medcodes (need for diagnosis date (cleaned) and Type 1 vs Type 2 (raw))
## This table has now been renamed to 'all_patid_raw_diabetes_medcodes'
#raw_diabetes_medcodes <- cprd$tables$observation %>% inner_join(codes$all_diabetes) %>% analysis$cached("raw_diabetes_medcodes",indexes=c("patid","obsdate","all_diabetes_cat"))

analysis = cprd$analysis("all_patid")
raw_diabetes_medcodes <- raw_diabetes_medcodes %>% analysis$cached("raw_diabetes_medcodes")


## All HbA1cs - could clean on import but do separately for now

analysis = cprd$analysis("all_patid")
raw_hba1c <- cprd$tables$observation %>%
  inner_join(codes$hba1c) %>%
  analysis$cached("raw_hba1c_medcodes",indexes=c("patid","obsdate","testvalue","numunitid"))

### This table has now been renamed to 'all_patid_clean_hba1c_medcodes'
#clean_hba1c <- raw_hba1c %>%
#  filter(year(obsdate)>=1990) %>%
#  mutate(testvalue=ifelse(testvalue<=20,((testvalue-2.152)/0.09148),testvalue)) %>%
#  clean_biomarker_units(testvalue, "hba1c") %>%
#  clean_biomarker_values(numunitid, "hba1c") %>%
#  group_by(patid,obsdate) %>% summarise(testvalue=mean(testvalue, na.rm=TRUE)) %>%
#  ungroup() %>% inner_join(cprd$tables$validDateLookup) %>%
#  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
#  select(patid,date=obsdate,testvalue) %>%
#  analysis$cached("clean_hba1c_medcodes",indexes=c("patid","date","testvalue"))

analysis = cprd$analysis("all_patid")
clean_hba1c_clean_units <- clean_hba1c_clean_units %>% analysis$cached("clean_hba1c_medcodes")


## All OHA scripts (need for diagnosis date (cleaned) and definition (cleaned))
## This table has now been renamed to 'all_patid_clean_oha_prodcodes'
#clean_oha <- cprd$tables$drugIssue %>%
#  inner_join(cprd$tables$ohaLookup) %>%
#  inner_join(cprd$tables$validDateLookup) %>%
#  filter(issuedate>=min_dob & issuedate<=gp_ons_end_date) %>%
#  select(patid,date=issuedate,dosageid,quantity,quantunitid,duration,INS,TZD,SU,DPP4,MFN,GLP1,Glinide,Acarbose,SGLT2) %>%
#  analysis$cached("clean_oha_prdcodes",indexes=c("patid","date","INS","TZD","SU","DPP4","MFN","GLP1","Glinide","Acarbose","SGLT2"))

clean_oha <- clean_oha %>% analysis$cached("clean_oha_prodcodes")


## All insulin scripts (need for diagnosis date (cleaned) and definition (cleaned))
## This table has now been renamed to 'all_patid_clean_insulin_prodcodes'
#clean_insulin <- cprd$tables$drugIssue %>%
#  inner_join(codes$insulin) %>%
#  inner_join(cprd$tables$validDateLookup) %>%
#  filter(issuedate>=min_dob & issuedate<=gp_ons_end_date) %>%
#  select(patid,date=issuedate,dosageid,quantity,quantunitid,duration) %>%
#  analysis$cached("clean_insulin_prodcodes",indexes=c("patid","date"))

clean_insulin <- clean_insulin %>% analysis$cached("clean_insulin_prodcodes")

analysis = cprd$analysis("katie_diagnosis_date")


# Cleaning required for diagnosis dates
## If construct query this way (finding earliest date from each of the diagnosis codes, HbA1cs and prescriptions, and then combining, rather than combining all dates and then finding earliest date, doesn't give Error 28 about disk space)

## Earliest clean (i.e. with valid date) non-family history diabetes medcode
first_diagnosis_dm_code <- raw_diabetes_medcodes %>%
  filter(obstypeid!=4) %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  group_by(patid) %>%
  summarise(date=min(obsdate,na.rm=TRUE)) %>%
  analysis$cached("first_diagnosis_dm_code", unique_index="patid")


## Earliest (clean) HbA1c >=48 mmol/mol
first_high_hba1c <- clean_hba1c_clean_units %>%
  filter(testvalue>47.5) %>%
  group_by(patid) %>%
  summarise(date=min(date,na.rm=TRUE)) %>%
  analysis$cached("first_high_hba1c", unique_index="patid")


## Earliest (clean) OHA script
first_oha <- clean_oha %>%
  group_by(patid) %>%
  summarise(date=min(date,na.rm=TRUE)) %>%
  analysis$cached("first_oha", unique_index="patid")


## Earliest (clean) insulin script
first_insulin <- clean_insulin %>%
  group_by(patid) %>%
  summarise(date=min(date,na.rm=TRUE)) %>%
  analysis$cached("first_insulin", unique_index="patid")



# Calculate diagnosis dates, and whether needs flag (if within 90 days of start of registration), and what type of code diagnosis is based on, and cache
# Also add gender, mob, yob, and registration start and end, practice ID, and cprd_ddate from patient table

dm_diag_dates <- t1t2_ids %>%
  left_join((first_diagnosis_dm_code %>% rename(dm_diag_dmcodedate=date)), by="patid") %>%
  left_join((first_high_hba1c %>% rename(dm_diag_hba1cdate=date)), by="patid") %>%
  left_join((first_oha %>% rename(dm_diag_ohadate=date)), by="patid") %>%
  left_join((first_insulin %>% rename(dm_diag_insdate=date)), by="patid") %>%
  
  mutate(dm_diag_date_all = pmin(ifelse(is.na(dm_diag_dmcodedate), as.Date("2050-01-01"), dm_diag_dmcodedate),
                             ifelse(is.na(dm_diag_hba1cdate), as.Date("2050-01-01"), dm_diag_hba1cdate),
                             ifelse(is.na(dm_diag_ohadate), as.Date("2050-01-01"), dm_diag_ohadate),
                             ifelse(is.na(dm_diag_insdate), as.Date("2050-01-01"), dm_diag_insdate), na.rm=TRUE),
         
         dm_diag_codetype = ifelse(is.na(dm_diag_date_all), NA,
                                   ifelse(!is.na(dm_diag_dmcodedate) & dm_diag_dmcodedate==dm_diag_date_all, 1L,
                                          ifelse(!is.na(dm_diag_hba1cdate) & dm_diag_hba1cdate==dm_diag_date_all, 2L,
                                                 ifelse(!is.na(dm_diag_ohadate) & dm_diag_ohadate==dm_diag_date_all, 3L, 4L))))) %>%
  
  inner_join(cprd$tables$patient, by="patid") %>%
  
  mutate(dm_diag_flag=(dm_diag_date_all>=regstartdate & datediff(dm_diag_date_all,regstartdate)<91)) %>%
  
  select(patid, gender, mob, yob, regstartdate, regenddate, pracid, cprd_ddate, starts_with("dm_diag")) %>%
  
  analysis$cached("dm_diag_dates", unique_indexes="patid",indexes="dm_diag_date_all")



################################################################################################################################

##################### TYPE 1 VS TYPE 2 #########################################################################################

# Make queries for variables requires

## Whether or not have valid insulin prescription
has_insulin <- clean_insulin %>%
  select(patid) %>%
  distinct() %>%
  mutate(has_insulin=1L) %>%
  analysis$cached("has_insulin",unique_indexes="patid")


## Type 1-specific code count (any date)
type1_code_count <- raw_diabetes_medcodes %>%
  filter(all_diabetes_cat=="Type 1") %>%
  group_by(patid) %>%
  summarise(type1_code_count=n()) %>%
  analysis$cached("type1_code_count",unique_indexes="patid")


## Type 2-specific code count (any date)
type2_code_count <-
  raw_diabetes_medcodes %>%
  filter(all_diabetes_cat=="Type 2") %>%
  group_by(patid) %>%
  summarise(type2_code_count=n()) %>%
  analysis$cached("type2_code_count",unique_indexes="patid")


## Age of diagnosis
### Also add in whether diagnosis date < regstartdate as will need this for time to insulin
dm_diag_dates_age <- dm_diag_dates %>%
  mutate(dob=as.Date(ifelse(is.na(mob),paste0(yob,"-07-01"),paste0(yob, "-",mob,"-15")))) %>%
  mutate(dm_diag_age_all=(datediff(dm_diag_date_all,dob))/365.25,dm_diag_before_reg=dm_diag_date_all<regstartdate) %>%
  select(patid, gender, dob, regstartdate, regenddate, pracid, cprd_ddate, starts_with("dm_diag")) %>%
  analysis$cached("dm_diag_dates_age", unique_indexes="patid",indexes=c("dm_diag_date_all","dm_diag_age_all"))


## Whether first insulin script within 1 year of diagnosis
time_to_insulin <- clean_insulin %>%
  group_by(patid) %>%
  summarise(first_insulin=min(date,na.rm=TRUE)) %>%
  ungroup() %>% inner_join(diag_dates_clean_hba1c) %>%
  filter((datediff(first_insulin,dm_diag_date_all))/365.25<=1) %>%
  mutate(ins_in_1_year=1L) %>% select(patid,ins_in_1_year) %>%
  analysis$cached("time_to_insulin",unique_indexes="patid")


## Current OHA status (whether have prescription for OHA in last 6 months of records)
current_oha <- clean_oha %>%
  group_by(patid) %>%
  summarise(latest_oha=max(date,na.rm=TRUE)) %>%
  ungroup() %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter((datediff(gp_ons_end_date,latest_oha))/365.25<=0.5) %>%
  mutate(current_oha=1L) %>%
  select(patid,current_oha) %>% analysis$cached("current_oha",unique_indexes="patid")


# Join together, find diabetes type, and cache
## Have included insulin within 1 year even if prescription is before registration start
## Also add in last collection date for practice, death date from ONS records, and whether has HES data from patidsWithLinkage lookup and derive/keep: regstartdate, gp_record_end (earliest of last collection date from practice, deregistration and 31/10/2020 (latest date in records)), death_date (earliest of 'cprddeathdate' (derived by CPRD) and ONS death date), and with_hes (patients with HES linkage and n_patid_hes<=20)

t1t2_cohort <- t1t2_ids %>%
  left_join(has_insulin,by="patid") %>%
  left_join(type1_code_count,by="patid") %>%
  left_join(type2_code_count,by="patid") %>%
  inner_join(dm_diag_dates_age, by="patid") %>%
  left_join(time_to_insulin,by="patid") %>%
  left_join(current_oha,by="patid") %>%
  replace_na(list(has_insulin=0L,type1_code_count=0L,type2_code_count=0L,ins_in_1_year=0L,current_oha=0L)) %>%
  mutate(diabetes_type=ifelse(
  (
      (has_insulin==1 & type1_code_count!=0 & type2_code_count!=0 & type1_code_count>=(2*type2_code_count)) |
      (has_insulin==1 & type1_code_count!=0 & type2_code_count==0) |
      (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all<35 & ins_in_1_year==1) |
      (has_insulin==1 & type1_code_count==0 & type2_code_count==0 & dm_diag_age_all<35 & dm_diag_before_reg==1 & current_oha==0)
    ),
  "type 1","type 2")) %>%
  
  left_join((cprd$tables$practice %>% select(pracid, lcd, region)), by="pracid") %>%
  left_join((cprd$tables$validDateLookup %>% select(patid, ons_death)), by="patid") %>%
  left_join((cprd$tables$patidsWithLinkage %>% select(patid, n_patid_hes)), by="patid") %>%
  
  mutate(gp_record_end=pmin(if_else(is.na(lcd), as.Date("2020-10-31"), lcd),
                            if_else(is.na(regenddate), as.Date("2020-10-31"), regenddate),
                            as.Date("2020-10-31"), na.rm=TRUE),
         
         death_date=pmin(if_else(is.na(cprd_ddate), as.Date("2050-01-01"), cprd_ddate),
                         if_else(is.na(ons_death), as.Date("2050-01-01"), ons_death), na.rm=TRUE),
         death_date=if_else(death_date==as.Date("2050-01-01"), as.Date(NA), death_date),
         
         with_hes=ifelse(!is.na(n_patid_hes) & n_patid_hes<=20, 1L, 0L)) %>%
  
  select(patid, gender, dob, pracid, prac_region=region, has_insulin, type1_code_count, type2_code_count, dm_diag_dmcodedate, dm_diag_hba1cdate, dm_diag_ohadate, dm_diag_insdate, dm_diag_date_all, dm_diag_codetype, dm_diag_flag, dm_diag_age_all, dm_diag_before_reg, ins_in_1_year, current_oha, diabetes_type, regstartdate, gp_record_end, death_date, with_hes) %>%
  
  analysis$cached("t1t2_cohort", unique_indexes="patid",indexes=c("gender", "dob", "dm_diag_date_all", "dm_diag_age_all", "diabetes_type"))


# all_t1t2_cohort is identical to katie_diagnosis_date_t1t2_cohort, except ethnicity added from all_patid_ethnicity - see all_patid_ethnicity_table script, IMD decile added from patientIMD2015, and Townsend score added from all_patid_townsend_score


################################################################################################################################

##################### FINALISE #################################################################################################

cprd$finalize()
rm(cprd)
rm(list=ls())