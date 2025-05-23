# Adds time to glycaemic failure to all drug class periods

# Glycaemic failure defined as two consecutive HbA1cs>threshold or one HbA1c>threshold where HbA1c is last before a drug is added

# Thresholds used:
## 7.5% (58.46 mmol/mol)
## 8.5% (69.39 mmol/mol)
## Baseline HbA1c
## Baseline HbA1c - 0.5% (5.47 mmol/mol)


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("mm")


############################################################################################

# Use cached baseline HbA1c and drug merge table (all drug periods merged with all clean HbA1c measurements) from baseline biomarkers script (02_mm_baseline_biomarkers)

baseline_biomarkers <- baseline_biomarkers %>% analysis$cached("baseline_biomarkers")

full_hba1c_drug_merge <- full_hba1c_drug_merge %>% analysis$cached("full_hba1c_drug_merge")


# And drug class periods with required variables from drug sorting script (01_mm_drug_sorting_and_combos)

drug_class_start_stop <- drug_class_start_stop %>% analysis$cached("drug_class_start_stop")

combo_class_start_stop <- combo_class_start_stop %>% analysis$cached("combo_class_start_stop")

drug_periods <- drug_class_start_stop %>%
left_join((combo_class_start_stop %>% select(patid, dcstartdate, nextdrugchange, nextdcdate, dcstartdate, timetochange_class, timetoaddrem_class)), by=c("patid","dstartdate_class"="dcstartdate")) %>%
  select(patid, dstartdate=dstartdate_class, dstopdate=dstopdate_class, drug_class, timetochange=timetochange_class, timetoaddrem=timetoaddrem_class, nextdrugchange, nextdcdate)


############################################################################################

# Code up glycaemic failure variables


# Make new table of all drug periods with baseline HbA1c and fail thresholds defined
## Thresholds need to be in same format as HbA1cs to able to compare

glycaemic_failure_thresholds <- drug_periods %>%
  inner_join((baseline_biomarkers %>% select(patid, dstartdate, drug_class, prehba1c, prehba1cdate)), by=c("patid", "dstartdate", "drug_class")) %>%
  distinct() %>%
  mutate(threshold_7.5=58,
         threshold_8.5=70,
         threshold_baseline=prehba1c,
         threshold_baseline_0.5=prehba1c-5.5) %>%
  analysis$cached("glycaemic_failure_thresholds", indexes=c("patid", "dstartdate", "drug_class"))

# Baseline biomarkers has duplicates for patid-dstartdate-drug_class for multiple substances - but prehba1c and prehba1cdate will be the same
# Same for full_hba1c_drug_merge below


# Join with HbA1cs during 'failure period' - more than 90 days after drugstart and no later than when diabetes drugs changed (doesn't take into account gaps)

glycaemic_failure_hba1cs <- glycaemic_failure_thresholds %>%
  left_join((full_hba1c_drug_merge %>% filter(drugdatediff>90) %>% distinct(patid, dstartdate, drug_class, testvalue, date)), by=c("patid", "dstartdate", "drug_class")) %>%
  filter(date<=nextdcdate) %>%
  group_by(patid, dstartdate, drug_class) %>%
  mutate(latest_fail_hba1c=max(date, na.rm=TRUE)) %>%
  ungroup() %>%
  analysis$cached("glycaemic_failure_hba1cs", indexes=c("patid", "dstartdate", "drug_class"))
  

# Make variables for each threshold:
## Fail date: earliest of nextdcdate, two consecutive HbA1cs over threshold, one HbA1c over threshold followed by drug being added (before next HbA1c) - within 'failure period' defined as above
## Fail reason: which of the above 3 scenarios the fail date represents

thresholds <- c("7.5", "8.5", "baseline", "baseline_0.5")

glycaemic_failure <- glycaemic_failure_hba1cs

for (i in thresholds) {
  
  threshold_value <- paste0("threshold_", i)
  fail_date <- paste0("hba1c_fail_", i, "_date")
  fail_reason <- paste0("hba1c_fail_", i, "_reason")
  
  glycaemic_failure <- glycaemic_failure %>%
    group_by(patid, dstartdate, drug_class) %>%
    dbplyr::window_order(date) %>%
    
    mutate(threshold_double=ifelse(testvalue>!!as.name(threshold_value) & lead(testvalue)>!!as.name(threshold_value), 1L, 0L),
           threshold_single_and_add=ifelse(testvalue>!!as.name(threshold_value) & date==latest_fail_hba1c & nextdrugchange=="add", 1L, 0L),
           fail_date=if_else((!is.na(threshold_double) & threshold_double==1) | (!is.na(threshold_single_and_add) & threshold_single_and_add==1), date,
                             if_else(is.na(!!as.name(threshold_value)), as.Date(NA), nextdcdate)),
           threshold_double_period=max(threshold_double, na.rm=TRUE),
           threshold_single_and_add_period=max(threshold_single_and_add, na.rm=TRUE),
           {{fail_date}}:=min(fail_date, na.rm=TRUE),
           {{fail_reason}}:=ifelse(is.na(!!as.name(threshold_value)), NA,
                                   ifelse(!is.na(threshold_double) & threshold_double_period==1, "Fail - 2 HbA1cs >threshold",
                                          ifelse(!is.na(threshold_single_and_add) & threshold_single_and_add_period==1, "Fail - 1 HbA1cs >threshold then add drug",
                                                 ifelse(nextdcdate==dstopdate, "End of prescriptions", "Change in diabetes drugs"))))) %>%
    
    ungroup() %>%
    
    select(-c(threshold_double, threshold_single_and_add, fail_date, threshold_double_period, threshold_single_and_add_period))
    
}

glycaemic_failure <- glycaemic_failure %>%
  group_by(patid, dstartdate, drug_class) %>%
  filter(row_number()==1) %>%
  ungroup() %>%
  dbplyr::window_order(patid, dstartdate, drug_class) %>%
  select(-c(testvalue, date, latest_fail_hba1c)) %>%
  analysis$cached("glycaemic_failure_interim", indexes=c("patid", "dstartdate", "drug_class"))
  

############################################################################################

# Add in whether threshold was ever reached (obviously not very useful for baseline threshold, but do want for others)

## Join failure dates and thresholds with HbA1cs going right back to and including baseline HbA1c and no later than when diabetes drugs changed (doesn't take into account gaps) so that we can find if they were ever at/below the threshold

glycaemic_failure_threshold_hba1cs <- glycaemic_failure %>%
  inner_join((full_hba1c_drug_merge %>%
               distinct(patid, dstartdate, drug_class, testvalue, date)), by=c("patid", "dstartdate", "drug_class")) %>%
  filter(date<=nextdcdate & date>=prehba1cdate) %>%
  select(patid, dstartdate, drug_class, testvalue, date) %>%
  analysis$cached("glycaemic_failure_threshold_hba1cs_interim", indexes=c("patid", "dstartdate", "drug_class"))

glycaemic_failure_threshold_hba1cs <- glycaemic_failure %>%
  left_join(glycaemic_failure_threshold_hba1cs, by=c("patid", "dstartdate", "drug_class")) %>%
  analysis$cached("glycaemic_failure_threshold_hba1cs", indexes=c("patid", "dstartdate", "drug_class"))


## Fail threshold reached: whether there is an HbA1c at/below the threshold value prior to failure

glycaemic_failure_thresholds_reached <- glycaemic_failure_threshold_hba1cs

for (i in thresholds) {
  
  threshold_value <- paste0("threshold_", i)
  fail_date <- paste0("hba1c_fail_", i, "_date")
  fail_threshold_reached <- paste0("hba1c_fail_", i, "_reached")
  
  glycaemic_failure_thresholds_reached <- glycaemic_failure_thresholds_reached %>%
    group_by(patid, dstartdate, drug_class) %>%
    
    mutate(threshold_reached=ifelse(!is.na(testvalue) & testvalue<=!!as.name(threshold_value) & date<=!!as.name(fail_date), 1L, 0L),
           threshold_reached=ifelse(is.na(!!as.name(threshold_value)), NA, threshold_reached),
           {{fail_threshold_reached}}:=max(threshold_reached, na.rm=TRUE)) %>%
    
    ungroup() %>%
    
    select(-threshold_reached)
  
}

glycaemic_failure_thresholds_reached <- glycaemic_failure_thresholds_reached %>%
  group_by(patid, dstartdate, drug_class) %>%
  filter(row_number()==1) %>%
  ungroup() %>%
  dbplyr::window_order(patid, dstartdate, drug_class) %>%
  select(-c(testvalue, date)) %>%
  relocate(hba1c_fail_7.5_reached, .after=hba1c_fail_7.5_reason) %>%
  relocate(hba1c_fail_8.5_reached, .after=hba1c_fail_8.5_reason) %>%
  relocate(hba1c_fail_baseline_reached, .after=hba1c_fail_baseline_reason) %>%
  relocate(hba1c_fail_baseline_0.5_reached, .after=hba1c_fail_baseline_0.5_reason) %>%
  analysis$cached("glycaemic_failure", indexes=c("patid", "dstartdate", "drug_class"))

