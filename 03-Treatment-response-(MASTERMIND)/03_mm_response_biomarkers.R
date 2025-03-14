
# Extracts 6 month and 12 month response biomarkers
## 6 month response: must be at least 3 months from drug start date, before another drug class added/removed, and no later than drug stop date + 91 days
## 12 month response: must be at least 9 months from drug start date, before another drug class added/removed, and no later than drug stop date + 91 days

# (Unlike for baseline biomarkers): only want for first instances of drug class (i.e. not where patient has taken drug, stopped, and then restarted)
# HbA1c only: response missing where timeprevcombo<=61 days before drug initiation

# All biomarker tests merged with all drug start and stop dates (plus timetochange, timeaddrem and multi_drug_start from mm_combo_start_stop = combination start stop table) in script 02_mm_baseline_biomarkers - tables created have names of the form 'mm_full_{biomarker}_drug_merge'

# Also finds date of next eGFR measurement post-baseline and date of 40%/50% decline in eGFR outcome (if present)
# And whether microalbuminuria at baseline is confirmed, and date of new macroalbuminuria (ACR>30 mg/mmol)


############################################################################################

# Setup
library(tidyverse)
library(aurum)
library(EHRBiomarkr)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")
#codesets = cprd$codesets()
#codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("mm")


############################################################################################

# Define biomarkers (can include HbA1c as processed the same as others; don't include height)
## If you add biomarker to the end of this list, code should run fine to incorporate new biomarker, as long as you delete final 'mm_response_biomarkers' table

biomarkers <- c("weight", "bmi", "fastingglucose", "hdl", "triglyceride", "creatinine_blood", "ldl", "alt", "ast", "totalcholesterol", "dbp", "sbp", "acr", "hba1c", "egfr", "albumin_blood", "bilirubin", "haematocrit", "haemoglobin", "pcr", "acr_from_separate")


############################################################################################

# Pull out 6 month and 12 month biomarker values

## Loop through full biomarker drug merge tables

## Just keep first instance

## Define earliest (min) and latest (last) valid date for each response length (6m and 12m)
### Earliest = 3 months for 6m response/9 months for 12m response
### Latest = minimum of timetochange + 91 days, timetoaddrem and 9 months (for 6m response)/15 months (for 12m response)

## Then use closest date to 6/12 months post drug start date
### May be multiple values; use minimum
### Can get duplicates where person has identical results on the same day/days equidistant from 6/12 months post drug start - choose first row when ordered by drugdatediff

# Then combine with baseline values and find response
## Remove HbA1c responses where timeprevcombo<=61 days i.e. where change glucose-lowering meds less than 61 days before current drug initiation


# 6 month response

for (i in biomarkers) {
  
  print(i)
  
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  post6m_table_name <- paste0("post6m_", i)
  
  drug_merge_tablename <- drug_merge_tablename %>% analysis$cached(drug_merge_tablename)
  
  data <- drug_merge_tablename %>%
    
    filter(drug_instance==1)  %>%
    
    mutate(minvaliddate6m = sql("date_add(dstartdate, interval 91 day)"),
           
           # pmin gets translated to SQL LEAST which doesn't like missing values
           maxtime6m = pmin(ifelse(is.na(timetoaddrem_class), 274, timetoaddrem_class),
                            ifelse(is.na(timetochange_class), 274, timetochange_class+91), 274, na.rm=TRUE),
           
           lastvaliddate6m=if_else(maxtime6m<91, NA, sql("date_add(dstartdate, interval maxtime6m day)"))) %>%
    
    filter(date>=minvaliddate6m & date<=lastvaliddate6m) %>%
    
    group_by(patid, dstartdate, drug_substance) %>%
    
    mutate(min_timediff=min(abs(183-drugdatediff), na.rm=TRUE)) %>%
    filter(abs(183-drugdatediff)==min_timediff) %>%
    
    mutate(post_biomarker_6m=min(testvalue, na.rm=TRUE)) %>%
    filter(post_biomarker_6m==testvalue) %>%
    
    rename(post_biomarker_6mdate=date,
           post_biomarker_6mdrugdiff=drugdatediff) %>%
    
    dbplyr::window_order(post_biomarker_6mdrugdiff) %>%
    filter(row_number()==1) %>%
    
    ungroup() %>%
    
    select(patid, dstartdate, drug_class, drug_substance, post_biomarker_6m, post_biomarker_6mdate, post_biomarker_6mdrugdiff) %>%
    
    analysis$cached(post6m_table_name, indexes=c("patid", "dstartdate", "drug_substance"))
  
  assign(post6m_table_name, data)
  
}


# 12 month response

for (i in biomarkers) {
  
  print(i)
  
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  post12m_table_name <- paste0("post12m_", i)
  
  drug_merge_tablename <- drug_merge_tablename %>% analysis$cached(drug_merge_tablename)
  
  data <- drug_merge_tablename %>%
    
    filter(drug_instance==1)  %>%
    
    mutate(minvaliddate12m = sql("date_add(dstartdate, interval 274 day)"),
           
           # pmin gets translated to SQL LEAST which doesn't like missing values
           maxtime12m = pmin(ifelse(is.na(timetoaddrem_class), 457, timetoaddrem_class),
                             ifelse(is.na(timetochange_class), 457, timetochange_class+91), 457, na.rm=TRUE),
           
           lastvaliddate12m=if_else(maxtime12m<274, NA, sql("date_add(dstartdate, interval maxtime12m day)"))) %>%
    
    filter(date>=minvaliddate12m & date<=lastvaliddate12m) %>%
    
    group_by(patid, dstartdate, drug_substance) %>%
    
    mutate(min_timediff=min(abs(365-drugdatediff), na.rm=TRUE)) %>%
    filter(abs(365-drugdatediff)==min_timediff) %>%
    
    mutate(post_biomarker_12m=min(testvalue, na.rm=TRUE)) %>%
    filter(post_biomarker_12m==testvalue) %>%
    
    rename(post_biomarker_12mdate=date,
           post_biomarker_12mdrugdiff=drugdatediff) %>%
    
    dbplyr::window_order(post_biomarker_12mdrugdiff) %>%
    filter(row_number()==1) %>%
    
    ungroup() %>%
    
    select(patid, dstartdate, drug_class, drug_substance, post_biomarker_12m, post_biomarker_12mdate, post_biomarker_12mdrugdiff) %>%
    
    analysis$cached(post12m_table_name, indexes=c("patid", "dstartdate", "drug_substance"))
  
  assign(post12m_table_name, data)
  
}


# Combine with baseline values and find response

baseline_biomarkers <- baseline_biomarkers %>% analysis$cached("baseline_biomarkers")
combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop")

response_biomarkers <- baseline_biomarkers %>%
  left_join((combo_start_stop %>% select(patid, dcstartdate, timeprevcombo_class)), by=c("patid", "dstartdate"="dcstartdate")) %>%
  filter(drug_instance==1)


for (i in biomarkers) {
  
  print(i)
  
  post6m_table <- get(paste0("post6m_", i))
  post12m_table <- get(paste0("post12m_", i))

  pre_biomarker_variable <- as.symbol(paste0("pre", i))
  pre_biomarker_date_variable <- as.symbol(paste0("pre", i, "date"))
  pre_biomarker_drugdiff_variable <- as.symbol(paste0("pre", i, "drugdiff"))
  
  post_6m_biomarker_variable <- paste0("post", i, "6m")
  post_6m_biomarker_date_variable <- paste0("post", i, "6mdate")
  post_6m_biomarker_drugdiff_variable <- paste0("post", i, "6mdrugdiff")
  biomarker_6m_response_variable <- paste0(i, "resp6m")
  post_12m_biomarker_variable <- paste0("post", i, "12m")
  post_12m_biomarker_date_variable <- paste0("post", i, "12mdate")
  post_12m_biomarker_drugdiff_variable <- paste0("post", i, "12mdrugdiff")
  biomarker_12m_response_variable <- paste0(i, "resp12m")
  
  interim_response_biomarker_table <- paste0("response_biomarkers_interim_", i)
  
  response_biomarkers <- response_biomarkers %>%
    left_join((post6m_table %>% select(-drug_class)), by=c("patid", "dstartdate", "drug_substance")) %>%
    left_join((post12m_table %>% select(-drug_class)), by=c("patid", "dstartdate", "drug_substance"))
  
  
  if (i=="hba1c") {
    response_biomarkers <- response_biomarkers %>%
      mutate(post_biomarker_6m=ifelse(!is.na(timeprevcombo_class) & timeprevcombo_class<=61, NA, post_biomarker_6m),
             post_biomarker_6mdate=if_else(!is.na(timeprevcombo_class) & timeprevcombo_class<=61, as.Date(NA), post_biomarker_6mdate),
             post_biomarker_6mdrugdiff=ifelse(!is.na(timeprevcombo_class) & timeprevcombo_class<=61, NA, post_biomarker_6mdrugdiff),
             post_biomarker_12m=ifelse(!is.na(timeprevcombo_class) & timeprevcombo_class<=61, NA, post_biomarker_12m),
             post_biomarker_12mdate=if_else(!is.na(timeprevcombo_class) & timeprevcombo_class<=61, as.Date(NA), post_biomarker_12mdate),
             post_biomarker_12mdrugdiff=ifelse(!is.na(timeprevcombo_class) & timeprevcombo_class<=61, NA, post_biomarker_12mdrugdiff))
  }
   
   
  response_biomarkers <- response_biomarkers %>%
    relocate(pre_biomarker_variable, .before=post_biomarker_6m) %>%
    relocate(pre_biomarker_date_variable, .before=post_biomarker_6m) %>%
    relocate(pre_biomarker_drugdiff_variable, .before=post_biomarker_6m) %>%
    
    mutate({{biomarker_6m_response_variable}}:=ifelse(!is.na(pre_biomarker_variable) & !is.na(post_biomarker_6m), post_biomarker_6m-pre_biomarker_variable, NA),
           {{biomarker_12m_response_variable}}:=ifelse(!is.na(pre_biomarker_variable) & !is.na(post_biomarker_12m), post_biomarker_12m-pre_biomarker_variable, NA)) %>%
    
    rename({{post_6m_biomarker_variable}}:=post_biomarker_6m,
           {{post_6m_biomarker_date_variable}}:=post_biomarker_6mdate,
           {{post_6m_biomarker_drugdiff_variable}}:=post_biomarker_6mdrugdiff,
           {{post_12m_biomarker_variable}}:=post_biomarker_12m,
           {{post_12m_biomarker_date_variable}}:=post_biomarker_12mdate,
           {{post_12m_biomarker_drugdiff_variable}}:=post_biomarker_12mdrugdiff) %>%
    
    analysis$cached(interim_response_biomarker_table, indexes=c("patid", "dstartdate", "drug_substance"))
  
}


############################################################################################

# Additional kidney outcomes

## eGFR

### Add in next eGFR measurement

analysis = cprd$analysis("all")

egfr_long <- egfr_long %>% analysis$cached("patid_clean_egfr_medcodes")

analysis = cprd$analysis("mm")

next_egfr <- baseline_biomarkers %>%
  select(patid, drug_substance, dstartdate, preegfrdate) %>%
  left_join(egfr_long, by="patid") %>%
  filter(datediff(date, preegfrdate)>0) %>%
  group_by(patid, drug_substance, dstartdate) %>%
  summarise(next_egfr_date=min(date, na.rm=TRUE)) %>%
  analysis$cached("response_biomarkers_next_egfr", indexes=c("patid", "dstartdate", "drug_substance"))


### Add in 40% decline in eGFR outcome
### Join drug start dates with all longitudinal eGFR measurements, and only keep later eGFR measurements which are <=60% of the baseline value
### Checked and those with null eGFR do get dropped
egfr40 <- baseline_biomarkers %>%
  select(patid, drug_substance, dstartdate, preegfr, preegfrdate) %>%
  left_join(egfr_long, by="patid") %>%
  filter(datediff(date, preegfrdate)>0 & testvalue<=0.6*preegfr) %>%
  group_by(patid, drug_substance, dstartdate, preegfr) %>%
  summarise(egfr_40_decline_date=min(date, na.rm=TRUE)) %>%
  ungroup() %>%
  left_join(egfr_long, by="patid") %>%
  filter(datediff(date, egfr_40_decline_date)>=28 & testvalue<=0.6*preegfr) %>%
  distinct(patid, drug_substance, dstartdate, egfr_40_decline_date) %>%
  analysis$cached("response_biomarkers_egfr40", indexes=c("patid", "dstartdate", "drug_substance"))


### Add in 50% decline in eGFR outcome
### Join drug start dates with all longitudinal eGFR measurements, and only keep later eGFR measurements which are <=50% of the baseline value
### Checked and those with null eGFR do get dropped
egfr50 <- baseline_biomarkers %>%
  select(patid, drug_substance, dstartdate, preegfr, preegfrdate) %>%
  left_join(egfr_long, by="patid") %>%
  filter(datediff(date, preegfrdate)>0 & testvalue<=0.5*preegfr) %>%
  group_by(patid, drug_substance, dstartdate, preegfr) %>%
  summarise(egfr_50_decline_date=min(date, na.rm=TRUE)) %>%
  ungroup() %>%
  left_join(egfr_long, by="patid") %>%
  filter(datediff(date, egfr_50_decline_date)>=28 & testvalue<=0.5*preegfr) %>%
  distinct(patid, drug_substance, dstartdate, egfr_50_decline_date) %>%
  analysis$cached("response_biomarkers_egfr50", indexes=c("patid", "dstartdate", "drug_substance"))


## ACR

### Add in whether baseline microalbuminuria is confirmed by previous or next measurement

analysis = cprd$analysis("all")

#### First combine all ACR readings - if both on same day, use value not from separate (no duplicate patid-date combos in either clean_acr_medcodes or clean_acr_from_separate_medcodes tables)
acr_together <- acr_together %>% analysis$cached("patid_clean_acr_medcodes")
acr_separate <- acr_separate %>% analysis$cached("patid_clean_acr_from_separate_medcodes")

acr_long <- acr_together %>%
  mutate(source="together") %>%
  union_all((acr_separate %>% mutate(source="separate"))) %>%
  group_by(patid, date) %>%
  mutate(count=n()) %>%
  ungroup() %>%
  filter(count==1 | (count==2 & source=="together")) %>%
  select(patid, date, testvalue) %>%
  analysis$cached("patid_acr_long", indexes=c("patid", "date", "testvalue"))


analysis = cprd$analysis("mm")

prev_acr <- baseline_biomarkers %>%
  select(patid, dstartdate, drug_substance, preacrdate) %>%
  left_join(acr_long, by="patid") %>%
  group_by(patid, dstartdate, drug_substance, preacrdate) %>%
  dbplyr::window_order(date) %>%
  mutate(preacr_previous=ifelse(row_number()==1, NA, lag(testvalue)),
         preacr_previous_date=ifelse(row_number()==1, NA, lag(date)),
         preacr_next = ifelse(row_number()==n(), NA, lead(testvalue)),
         preacr_next_date=ifelse(row_number()==n(), NA, lead(date))) %>%
  ungroup() %>%
  analysis$cached("response_biomarkers_acr_confirmed_interim", indexes=c("patid", "dstartdate", "drug_substance"))

prev_acr <- prev_acr %>%
  filter(date==preacrdate) %>%
  mutate(preacr_confirmed = ifelse(testvalue >= 3 & (preacr_previous >= 3 & datediff(preacr_previous_date, preacrdate) <=7 & datediff(preacr_previous_date, preacrdate) >= -730 | preacr_next >= 3), TRUE, FALSE)) %>%
  select(patid, dstartdate, drug_substance, preacr_confirmed, preacr_previous, preacr_previous_date, preacr_next, preacr_next_date) %>%
  analysis$cached("response_biomarkers_acr_confirmed", indexes=c("patid", "dstartdate", "drug_substance"))


### Add in new macroalbuminuria for those with confirmed microalbuminuria at baseline

new_macroalb <- baseline_biomarkers %>%
  select(patid, dstartdate, drug_substance, preacrdate) %>%
  left_join(acr_long, by="patid") %>%
  left_join(prev_acr, by=c("patid", "dstartdate", "drug_substance")) %>%
  filter(date>preacrdate) %>%
  analysis$cached("response_biomarkers_macroalb_interim", indexes=c("patid", "dstartdate", "drug_substance"))

new_macroalb <- new_macroalb %>%
  group_by(patid, dstartdate, drug_substance) %>%
  dbplyr::window_order(date) %>%
  mutate(nextvalue = lead(testvalue)) %>%
  ungroup() %>%
  analysis$cached("response_biomarkers_macroalb_interim_2", indexes=c("patid", "dstartdate", "drug_substance"))

new_macroalb <- new_macroalb %>%
  filter(preacr_confirmed == T & testvalue >=30 | 
           preacr_confirmed == F & testvalue >=30 & nextvalue >=30) %>%
  group_by(patid, drug_substance, dstartdate) %>%
  summarise(macroalb_date=min(date, na.rm=TRUE)) %>%
  ungroup() %>%
  analysis$cached("response_biomarkers_macroalb", indexes=c("patid", "dstartdate", "drug_substance"))


############################################################################################

# Join to rest of response dataset and move where height variable is

response_biomarkers <- response_biomarkers %>%
  left_join(next_egfr, by=c("patid", "drug_substance", "dstartdate")) %>%
  left_join(egfr40, by=c("patid", "drug_substance", "dstartdate")) %>%
  left_join(egfr50, by=c("patid", "drug_substance", "dstartdate")) %>%
  left_join(prev_acr, by=c("patid", "drug_substance", "dstartdate")) %>%
  left_join(new_macroalb, by=c("patid", "drug_substance", "dstartdate")) %>%
  relocate(height, .after=timeprevcombo_class) %>%
  relocate(prehba1c12m, .after=hba1cresp12m) %>%
  relocate(prehba1c12mdate, .after=prehba1c12m) %>%
  relocate(prehba1c12mdrugdiff, .after=prehba1c12mdate) %>%
  relocate(prehba1c2yrs, .after=hba1cresp12m) %>%
  relocate(prehba1c2yrsdate, .after=prehba1c2yrs) %>%
  relocate(prehba1c2yrsdrugdiff, .after=prehba1c2yrsdate) %>%
  analysis$cached("response_biomarkers", indexes=c("patid", "dstartdate", "drug_substance"))
