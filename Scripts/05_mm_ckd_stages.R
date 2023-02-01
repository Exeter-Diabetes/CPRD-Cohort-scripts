
# Calculates CKD stages using eGFR readings:
## Only keep CKD stages if >1 consecutive test with the same stage, and if time between earliest and latest consecutive test with same stage are >=90 days apart
## Combine with CKD5 medcodes
## Find start date for each CKD stage
## Define baseline CKD stage at each drug start date

############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
#codesets = cprd$codesets()
#codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("mm")
# Store in 'all_patid' tables until merge with drug dates


############################################################################################

# Get clean eGFR readings 

analysis = cprd$analysis("all_patid")

clean_egfr_medcodes <- clean_egfr_medcodes %>% analysis$cached("clean_egfr_medcodes")

clean_egfr_medcodes %>% count()
#24,925,444


################################################################################################################################

# Convert eGFR to CKD stage

ckd_stages_from_all_egfr <- clean_egfr_medcodes %>%
  mutate(ckd_stage=ifelse(testvalue<15, "stage_5",
                          ifelse(testvalue<30, "stage_4",
                                 ifelse(testvalue<45, "stage_3b",
                                        ifelse(testvalue<60, "stage_3a",
                                               ifelse(testvalue<90, "stage_2",
                                                      ifelse(testvalue>=90, "stage_1", NA)))))))


################################################################################################################################

# Only keep CKD stages if >1 consecutive test with the same stage, and if time between earliest and latest consecutive test with same stage are >=90 days apart

## For each patient:
### A) Define period from current test until next test as having the ckd_stage of current test
### B) Join together consecutive periods with the same ckd_stage
### C) If period contains >1 test, and there is >=90 days between the first and last test in the period, it is 'confirmed'


### A) Define period from current test until next test as having the ckd_stage of current test

#### Add in row labelling within each patient's values + max number of rows for each patient

ckd_stages_from_algorithm <- ckd_stages_from_all_egfr %>%
  group_by(patid) %>%
  dbplyr::window_order(date) %>%
  mutate(patid_row_id=row_number()) %>%
  mutate(patid_total_rows=max(patid_row_id, na.rm=TRUE)) %>%
  ungroup()


#### For rows where there is a next test, use this as end date; for last row, use start date as end date

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>%
  mutate(next_row=patid_row_id+1) %>%
  left_join(ckd_stages_from_algorithm, by=c("patid","next_row"="patid_row_id")) %>%
  mutate(ckd_start=date.x,
         ckd_end=if_else(is.na(date.y),date.x,date.y),
         ckd_stage=ckd_stage.x) %>%
  select(patid, patid_row_id, ckd_stage, ckd_start, ckd_end)


### B) Join together consecutive periods with the same ckd_stage

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>%
  group_by(patid, ckd_stage) %>%
  dbplyr::window_order(patid, ckd_stage, patid_row_id) %>%
  mutate(lead_var=lead(ckd_start),
         cummax_var=cummax(ckd_end)) %>%
  mutate(compare=cumsum(lead_var>cummax_var)) %>%
  mutate(indx=ifelse(row_number()==1, 0L, lag(compare))) %>%
  ungroup() %>%
  group_by(patid, ckd_stage ,indx) %>%
  summarise(first_test_date=min(ckd_start,na.rm=TRUE),
            last_test_date=max(ckd_start,na.rm=TRUE),
            end_date=max(ckd_end,na.rm=TRUE),
            test_count=max(patid_row_id, na.rm=TRUE)-min(patid_row_id, na.rm=TRUE)+1) %>%
  ungroup() %>%
  analysis$cached("ckd_stages_from_algorithm_interim_1",indexes=c("patid", "ckd_stage", "test_count", "first_test_date", "last_test_date"))
  
ckd_stages_from_algorithm %>% count()
#7,023,899

ckd_stages_from_algorithm %>% summarise(total=sum(test_count, na.rm=TRUE))
#total number of tests: 24,925,444 as above


### C) Remove periods with 1 reading, or with multiple readings but <90 days between first and last test, and cache

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>%
  filter(test_count>1 & datediff(last_test_date, first_test_date)>=90) %>%
  analysis$cached("ckd_stages_from_algorithm_interim_2",indexes=c("patid","ckd_stage","first_test_date"))

ckd_stages_from_algorithm %>% count()
#3,423,316


################################################################################################################################

# Combine with CKD5 medcodes/ICD10/OPCS4 codes

## Get raw CKD5 codes and clean
### All are already in all_patid tables on MySQL from 4_mm_comorbidities script

### Medcodes
analysis = cprd$analysis("all_patid")
raw_ckd5_code_medcodes <- raw_ckd5_medcodes %>% analysis$cached("raw_ckd5_code_medcodes")

### ICD10 codes
raw_ckd5_code_icd10 <- raw_ckd5_icd10 %>% analysis$cached("raw_ckd5_code_icd10")

### OPCS4 codes
raw_ckd5_code_opcs4 <- raw_ckd5_opcs4 %>% analysis$cached("raw_ckd5_code_opcs4")


## Clean, find earliest date per person, and re-cache

earliest_clean_ckd5 <- raw_ckd5_code_medcodes %>%
  select(patid, date=obsdate) %>%
  mutate(source="gp") %>%
  union_all((raw_ckd5_code_icd10 %>% select(patid, date=epistart) %>% mutate(source="hes"))) %>%
  union_all((raw_ckd5_code_opcs4 %>% select(patid, date=evdate) %>% mutate(source="hes"))) %>%
  inner_join(cprd$tables$validDateLookup) %>%
  filter(date>=min_dob & ((source=="gp" & date<=gp_ons_end_date) | (source=="hes" & (is.na(gp_ons_death_date) | date<=gp_ons_death_date)))) %>%
  group_by(patid) %>%
  summarise(first_test_date=min(date, na.rm=TRUE))%>%
  ungroup() %>%
  analysis$cached("earliest_clean_ckd5",indexes=c("patid", "first_test_date"))


## Combine CKD5 and other codes

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>%
  select(patid, ckd_stage, first_test_date) %>%
  union_all(earliest_clean_ckd5 %>% mutate(ckd_stage="stage_5")) %>%
  analysis$cached("ckd_stages_from_algorithm_interim_3",indexes=c("patid","ckd_stage","first_test_date"))

ckd_stages_from_algorithm %>% count()        
#3,477,914


################################################################################################################################

# Define date of onset for each stage

## For each person, define date of onset of each stage (earliest incident) - assume no returning to less severe stages

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>%
  group_by(patid, ckd_stage) %>%
  summarise(ckd_stage_start=min(first_test_date, na.rm=TRUE)) %>%
  ungroup()


## Remove where start date of less severe stage is later than start date of more severe stage
### Reshape wide first

ckd_stages_from_algorithm <- ckd_stages_from_algorithm %>%
  pivot_wider(patid,
              names_from=ckd_stage,
              values_from=ckd_stage_start) %>%
  mutate(stage_1=ifelse(!is.na(stage_1) & !is.na(stage_2) & stage_1>stage_2, NA, stage_1),
         stage_1=ifelse(!is.na(stage_1) & !is.na(stage_3a) & stage_1>stage_3a, NA, stage_1),
         stage_1=ifelse(!is.na(stage_1) & !is.na(stage_3b) & stage_1>stage_3b, NA, stage_1),
         stage_1=ifelse(!is.na(stage_1) & !is.na(stage_4) & stage_1>stage_4, NA, stage_1),
         stage_1=ifelse(!is.na(stage_1) & !is.na(stage_5) & stage_1>stage_5, NA, stage_1),
         stage_2=ifelse(!is.na(stage_2) & !is.na(stage_3a) & stage_2>stage_3a, NA, stage_2),
         stage_2=ifelse(!is.na(stage_2) & !is.na(stage_3b) & stage_2>stage_3b, NA, stage_2),
         stage_2=ifelse(!is.na(stage_2) & !is.na(stage_4) & stage_2>stage_4, NA, stage_2),
         stage_2=ifelse(!is.na(stage_2) & !is.na(stage_5) & stage_2>stage_5, NA, stage_2),
         stage_3a=ifelse(!is.na(stage_3a) & !is.na(stage_3b) & stage_3a>stage_3b, NA, stage_3a),
         stage_3a=ifelse(!is.na(stage_3a) & !is.na(stage_4) & stage_3a>stage_4, NA, stage_3a),
         stage_3a=ifelse(!is.na(stage_3a) & !is.na(stage_5) & stage_3a>stage_5, NA, stage_3a),
         stage_3b=ifelse(!is.na(stage_3b) & !is.na(stage_4) & stage_3b>stage_4, NA, stage_3b),
         stage_3b=ifelse(!is.na(stage_3b) & !is.na(stage_5) & stage_3b>stage_5, NA, stage_3b),
         stage_4=ifelse(!is.na(stage_4) & !is.na(stage_5) & stage_4>stage_5, NA, stage_4)) %>%
  analysis$cached("ckd_stages_from_algorithm", unique_indexes="patid")
                  

################################################################################################################################

# Merge with drug start dates to get CKD stages at drug start

# Get drug start dates (1 row per drug period)

analysis = cprd$analysis("mm")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")


# Merge with CKD stages (1 row per patid)

ckd_stage_drug_merge <- drug_start_stop %>%
  select(patid, dstartdate, drugclass, druginstance) %>%
  left_join(ckd_stages_from_algorithm, by="patid") %>%
  mutate(preckdstage=ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)<=7, "stage_5",
                            ifelse(!is.na(stage_4) & datediff(stage_4, dstartdate)<=7, "stage_4",
                                   ifelse(!is.na(stage_3b) & datediff(stage_3b, dstartdate)<=7, "stage_3b",
                                          ifelse(!is.na(stage_3a) & datediff(stage_3a, dstartdate)<=7, "stage_3a",
                                                 ifelse(!is.na(stage_2) & datediff(stage_2, dstartdate)<=7, "stage_2",
                                                        ifelse(!is.na(stage_1) & datediff(stage_1, dstartdate)<=7, "stage_1", NA)))))),
         
         preckdstagedate=ifelse(preckdstage=="stage_5", stage_5,
                                ifelse(preckdstage=="stage_4", stage_4,
                                       ifelse(preckdstage=="stage_3b", stage_3b,
                                              ifelse(preckdstage=="stage_3a", stage_3a,
                                                     ifelse(preckdstage=="stage_2", stage_2,
                                                            ifelse(preckdstage=="stage_1", stage_1, NA)))))),
         
         preckdstagedrugdiff=datediff(preckdstagedate, dstartdate),
         
         postckdstage345date=
           pmin(
             ifelse(!is.na(stage_3a) & datediff(stage_3a, dstartdate)>7, stage_3a, as.Date("2050-01-01")),
             ifelse(!is.na(stage_3b) & datediff(stage_3b, dstartdate)>7, stage_3b, as.Date("2050-01-01")),
             ifelse(!is.na(stage_4) & datediff(stage_4, dstartdate)>7, stage_4, as.Date("2050-01-01")),
             ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)>7, stage_5, as.Date("2050-01-01")), na.rm=TRUE
           ),
        
         postckdstage5date=ifelse(!is.na(stage_5) & datediff(stage_5, dstartdate)>7, stage_5, NA)) %>%
  
  mutate(postckdstage345date=ifelse(postckdstage345date==as.Date("2050-01-01"), as.Date(NA), postckdstage345date)) %>%
  
  select(patid, dstartdate, drugclass, druginstance, preckdstagedate, preckdstagedrugdiff, preckdstage, postckdstage5date, postckdstage345date) %>%
  
  analysis$cached("ckd_stages", indexes=c("patid", "dstartdate", "drugclass"))
                                
 