
# Extracts and cleans all biomarker values (and creates eGFR readings from creatinine)

# Merges with drug start and stop dates plus timetochange, timeaddrem, multi_drug_start, nextdrugchange and nextdcdate variables from mm_combo_start_stop (combination start and stop dates) table - first 3 variables needed for working out response biomarkers in script 03_mm_response_biomarkers; nextdrugchange and nextdcdate needed for HbA1c for glycaemic failure in 09_mm_glycaemic_failure

# Merges with drug start and stop dates plus timetochange, timeaddrem, multi_drug_start, nextdrugchange and nextdcdate variables from mm_combo_start_stop (combination start and stop dates) table - first 3 variables needed for working out response biomarkers in script 03_mm_response_biomarkers

# Finds biomarker values at baseline: -2 years to +7 days relative to drug start for all except:
## HbA1c: -6 months to +7 days, and excludes any before timeprevcombo
## SBP: -6 months to +7 days, and excludes any before timeprevcombo
## DBP: -6 months to +7 days, and excludes any before timeprevcombo
## Height: mean of all values >= drug start

# NB: creatinine_blood and eGFR tables may already have been cached as part of all_patid_ckd_stages script


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("pedro_BP_183")


############################################################################################

# Define biomarkers
## If you add biomarker to the end of this list, code should run fine to incorporate new biomarker, as long as you delete final 'mm_baseline_biomarkers' table

biomarkers <- c("hba1c", "sbp", "dbp", "acr_from_separate", "egfr", "weight", "height", "bmi", "fastingglucose", "hdl", "triglyceride", "creatinine_blood", "ldl", "alt", "ast", "totalcholesterol", "acr", "albumin_blood", "bilirubin", "haematocrit", "haemoglobin", "pcr")


############################################################################################

# Pull out all clean biomarker values

analysis = cprd$analysis("all_patid")

for (i in biomarkers) {
  
  # print current biomarkers
  print(i)
  # table name
  raw_tablename <- paste0("clean_", i, "_medcodes")
  # load clean table for biomarker
  data <- data %>%
    # cache this table (load)
    analysis$cached(raw_tablename, indexes=c("patid", "obsdate", "testvalue", "numunitid"))
  # cache table name
  assign(raw_tablename, data)
  
}


############################################################################################

# Combine each biomarker with start dates of all drug periods (not just first instances; with timetochange, timeaddrem and multi_drug_start added from mm_combo_start_stop table), and cache as separate tables

## Get drug start dates

analysis = cprd$analysis("pedro_BP_183")

drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")

combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop")


drug_start_dates <- drug_start_stop %>%
  # combine both datasets with left join
  left_join(
    combo_start_stop %>% 
      # select variables needed
      select(patid, dcstartdate, timetochange, timetoaddrem, multi_drug_start, nextdrugchange, nextdcdate), by=c("patid","dstartdate"="dcstartdate")) %>%
  # select variables needed
  select(patid, dstartdate, drugclass, druginstance, timetochange, timetoaddrem, multi_drug_start, nextdrugchange, nextdcdate)


## Merge with biomarkers and calculate date difference between biomarker and drug start date

for (i in biomarkers) {
  
  # biomarkers currently being used
  print(i)
  
  # name of biomarker table
  clean_tablename <- paste0("clean_", i, "_medcodes")
  # name of final table
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  
  # get the biomarker table needed
  data <- get(clean_tablename) %>%
    # join drug start dates (inner join to keep only those with information)
    inner_join(drug_start_dates, by="patid") %>%
    # create variable needed
    mutate(drugdatediff=datediff(date, dstartdate)) %>%
    # cache this table
    analysis$cached(drug_merge_tablename, indexes=c("patid", "dstartdate", "drugclass"))
  
  # assign new name
  assign(drug_merge_tablename, data)
  
}



############################################################################################

# Find baseline values
## Within period defined above (-2 years to +7 days for all except HbA1c and height)
## Then use closest date to drug start date
## May be multiple values; use minimum test result, except for eGFR - use maximum
## Can get duplicates where person has identical results on the same day/days equidistant from the drug start date - choose first row when ordered by drugdatediff

baseline_biomarkers <- drug_start_stop %>%
  select(patid, dstartdate, drugclass, druginstance)


## For all except height: between 2 years prior and 7 days after drug start date


biomarkers_no_height <- setdiff(biomarkers, "height")

for (i in biomarkers_no_height) {
  
  print(i)
  
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  interim_baseline_biomarker_table <- paste0("baseline_biomarkers_interim_", i)
  pre_biomarker_variable <- paste0("pre", i)
  pre_biomarker_date_variable <- paste0("pre", i, "date")
  pre_biomarker_drugdiff_variable <- paste0("pre", i, "drugdiff")
  
  
  data <- get(drug_merge_tablename) %>%
    filter(drugdatediff<=7 & drugdatediff>=-730) %>%
    
    group_by(patid, dstartdate, drugclass) %>%
    
    mutate(min_timediff=min(abs(drugdatediff), na.rm=TRUE)) %>%
    filter(abs(drugdatediff)==min_timediff) %>%
    
    mutate(pre_biomarker=ifelse(i=="egfr", max(testvalue, na.rm=TRUE), min(testvalue, na.rm=TRUE))) %>%
    filter(pre_biomarker==testvalue) %>%
    
    dbplyr::window_order(drugdatediff) %>%
    filter(row_number()==1) %>%
    
    ungroup() %>%
    
    relocate(pre_biomarker, .after=patid) %>%
    relocate(date, .after=pre_biomarker) %>%
    relocate(drugdatediff, .after=date) %>%
    
    rename({{pre_biomarker_variable}}:=pre_biomarker,
           {{pre_biomarker_date_variable}}:=date,
           {{pre_biomarker_drugdiff_variable}}:=drugdatediff) %>%
    
    select(-c(testvalue, druginstance, min_timediff, timetochange, timetoaddrem, multi_drug_start, nextdrugchange, nextdcdate))
  
  
  baseline_biomarkers <- baseline_biomarkers %>%
    left_join(data, by=c("patid", "dstartdate", "drugclass")) %>%
    analysis$cached(interim_baseline_biomarker_table, indexes=c("patid", "dstartdate", "drugclass"))
  
}


## Height - only keep readings at/post drug start date, and find mean

baseline_height <- full_height_drug_merge %>%
  
  filter(drugdatediff>=0) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
  
  summarise(height=mean(testvalue, na.rm=TRUE)) %>%
  
  ungroup()

baseline_biomarkers <- baseline_biomarkers %>%
  left_join(baseline_height, by=c("patid", "dstartdate", "drugclass"))



## HbA1c: have 2 year value from above; now add in between 6 months prior and 7 days after drug start date (for prehba1c) or between 12 months prior and 7 days after (for prehba1c12m)
## Exclude if before timeprevcombo for 6 month and 12 month value (not 2 year value)

baseline_hba1c <- full_hba1c_drug_merge %>%
  
  filter(drugdatediff<=7 & drugdatediff>=-366) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
  
  mutate(min_timediff=min(abs(drugdatediff), na.rm=TRUE)) %>%
  filter(abs(drugdatediff)==min_timediff) %>%
  
  mutate(prehba1c12m=min(testvalue, na.rm=TRUE)) %>%
  filter(prehba1c12m==testvalue) %>%
  
  dbplyr::window_order(drugdatediff) %>%
  filter(row_number()==1) %>%
  
  ungroup() %>%
  
  rename(prehba1c12mdate=date,
         prehba1c12mdrugdiff=drugdatediff) %>%
  
  mutate(prehba1c=ifelse(prehba1c12mdrugdiff>=-183, prehba1c12m, NA),
         prehba1cdate=ifelse(prehba1c12mdrugdiff>=-183, prehba1c12mdate, NA),
         prehba1cdrugdiff=ifelse(prehba1c12mdrugdiff>=-183, prehba1c12mdrugdiff, NA)) %>%
  
  select(patid, dstartdate, drugclass, prehba1c12m, prehba1c12mdate, prehba1c12mdrugdiff, prehba1c, prehba1cdate, prehba1cdrugdiff)



## SBP: have 2 year value from above; now add in between 6 months prior and 7 days after drug start date (for presbp) or between 12 months prior and 7 days after (for presbp12m)
## Exclude if before timeprevcombo for 6 month and 12 month value (not 2 year value)

baseline_sbp <- full_sbp_drug_merge %>%
  
  filter(drugdatediff<=7 & drugdatediff>=-366) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
  
  mutate(min_timediff=min(abs(drugdatediff), na.rm=TRUE)) %>%
  filter(abs(drugdatediff)==min_timediff) %>%
  
  mutate(presbp12m=min(testvalue, na.rm=TRUE)) %>%
  filter(presbp12m==testvalue) %>%
  
  dbplyr::window_order(drugdatediff) %>%
  filter(row_number()==1) %>%
  
  ungroup() %>%
  
  rename(presbp12mdate=date,
         presbp12mdrugdiff=drugdatediff) %>%
  
  mutate(presbp=ifelse(presbp12mdrugdiff>=-183, presbp12m, NA),
         presbpdate=ifelse(presbp12mdrugdiff>=-183, presbp12mdate, NA),
         presbpdrugdiff=ifelse(presbp12mdrugdiff>=-183, presbp12mdrugdiff, NA)) %>%
  
  select(patid, dstartdate, drugclass, presbp12m, presbp12mdate, presbp12mdrugdiff, presbp, presbpdate, presbpdrugdiff)



## DBP: have 2 year value from above; now add in between 6 months prior and 7 days after drug start date (for predbp) or between 12 months prior and 7 days after (for predbp12m)
## Exclude if before timeprevcombo for 6 month and 12 month value (not 2 year value)

baseline_dbp <- full_dbp_drug_merge %>%
  
  filter(drugdatediff<=7 & drugdatediff>=-366) %>%
  
  group_by(patid, dstartdate, drugclass) %>%
  
  mutate(min_timediff=min(abs(drugdatediff), na.rm=TRUE)) %>%
  filter(abs(drugdatediff)==min_timediff) %>%
  
  mutate(predbp12m=min(testvalue, na.rm=TRUE)) %>%
  filter(predbp12m==testvalue) %>%
  
  dbplyr::window_order(drugdatediff) %>%
  filter(row_number()==1) %>%
  
  ungroup() %>%
  
  rename(predbp12mdate=date,
         predbp12mdrugdiff=drugdatediff) %>%
  
  mutate(predbp=ifelse(predbp12mdrugdiff>=-183, predbp12m, NA),
         predbpdate=ifelse(predbp12mdrugdiff>=-183, predbp12mdate, NA),
         predbpdrugdiff=ifelse(predbp12mdrugdiff>=-183, predbp12mdrugdiff, NA)) %>%
  
  select(patid, dstartdate, drugclass, predbp12m, predbp12mdate, predbp12mdrugdiff, predbp, predbpdate, predbpdrugdiff)


### timeprevcombo in combo_start_stop table

combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop")

baseline_hba1c <- baseline_hba1c %>%
  left_join((combo_start_stop %>% select(patid, dcstartdate, timeprevcombo)), by=c("patid", c("dstartdate"="dcstartdate"))) %>%
  filter(prehba1c12mdrugdiff>=0 | is.na(timeprevcombo) | (!is.na(timeprevcombo) & abs(prehba1c12mdrugdiff)<=timeprevcombo)) %>%
  select(-timeprevcombo)

baseline_sbp <- baseline_sbp %>%
  left_join((combo_start_stop %>% select(patid, dcstartdate, timeprevcombo)), by=c("patid", c("dstartdate"="dcstartdate"))) %>%
  filter(presbp12mdrugdiff>=0 | is.na(timeprevcombo) | (!is.na(timeprevcombo) & abs(presbp12mdrugdiff)<=timeprevcombo)) %>%
  select(-timeprevcombo)

baseline_dbp <- baseline_dbp %>%
  left_join((combo_start_stop %>% select(patid, dcstartdate, timeprevcombo)), by=c("patid", c("dstartdate"="dcstartdate"))) %>%
  filter(predbp12mdrugdiff>=0 | is.na(timeprevcombo) | (!is.na(timeprevcombo) & abs(predbp12mdrugdiff)<=timeprevcombo)) %>%
  select(-timeprevcombo)


baseline_biomarkers <- baseline_biomarkers %>%
  rename(
    prehba1c2yrs=prehba1c,
         prehba1c2yrsdate=prehba1cdate,
         prehba1c2yrsdrugdiff=prehba1cdrugdiff,
    presbp2yrs=presbp,
    presbp2yrsdate=presbpdate,
    presbp2yrsdrugdiff=presbpdrugdiff,
    predbp2yrs=predbp,
    predbp2yrsdate=predbpdate,
    predbp2yrsdrugdiff=predbpdrugdiff,
    ) %>%
  left_join(baseline_hba1c, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(baseline_sbp, by=c("patid", "dstartdate", "drugclass")) %>%
  left_join(baseline_dbp, by=c("patid", "dstartdate", "drugclass")) %>%
  relocate(height, .after=prehba1cdrugdiff) %>%
  analysis$cached("baseline_biomarkers", indexes=c("patid", "dstartdate", "drugclass"))


