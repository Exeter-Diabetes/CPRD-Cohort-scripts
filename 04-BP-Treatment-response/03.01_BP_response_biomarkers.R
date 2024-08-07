
# Extracts 6 month and 12 month response biomarkers
## 3 month response: must be at least 3 months from drug start date, before another drug class added/removed, and no later than drug stop date + 30 days
## 6 month response: must be at least 3 months from drug start date, before another drug class added/removed, and no later than drug stop date + 91 days
## 12 month response: must be at least 9 months from drug start date, before another drug class added/removed, and no later than drug stop date + 91 days

# (Unlike for baseline biomarkers): only want for first instances of drug class (i.e. not where patient has taken drug, stopped, and then restarted)
# HbA1c only: response missing where timeprevcombo<=61 days before drug initiation

# All biomarker tests merged with all drug start and stop dates (plus timetochange, timeaddrem and multi_drug_start from mm_combo_start_stop = combination start stop table) in script 2_mm_baseline_biomarkers - tables created have names of the form 'mm_full_{biomarker}_drug_merge'

# Also finds date of next eGFR measurement post-baseline and date of 40% decline in eGFR outcome (if present)


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
#codesets = cprd$codesets()
#codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("pedro_BP")


############################################################################################

# Define biomarkers (can include HbA1c as processed the same as others; don't include height)
## If you add biomarker to the end of this list, code should run fine to incorporate new biomarker, as long as you delete final 'pedro_BP_response_biomarkers' table

biomarkers <- c("weight", "bmi", "fastingglucose", "hdl", "triglyceride", "creatinine_blood", "ldl", "alt", "ast", "totalcholesterol", "dbp", "sbp", "acr", "hba1c", "egfr", "albumin_blood", "bilirubin", "haematocrit", "haemoglobin", "pcr", "acr_from_separate")


############################################################################################

# Pull out 3 month and 6 month and 12 month biomarker values

## Loop through full biomarker drug merge tables

## Just keep first instance

## Define earliest (min) and latest (last) valid date for each response length (3m and 6m and 12m)
### Earliest = 3months for 3m response/3 months for 6m response/9 months for 12m response
### Latest = minimum of timetochange +30 days (3m response)/ + 91 days (6m and 12m response), timetoaddrem and 4 months (for 3m response)/9 months (for 6m response)/15 months (for 12m response)

## Then use closest date to 3/6/12 months post drug start date
### May be multiple values; use minimum
### Can get duplicates where person has identical results on the same day/days equidistant from 6/12 months post drug start - choose first row when ordered by drugdatediff

# Then combine with baseline values and find response
## Remove HbA1c/SBP/DBP responses where timeprevcombo<=61 days i.e. where change glucose-lowering meds less than 61 days before current drug initation


# 3 month response

for (i in biomarkers) {
  
  # print biomarker 
  print(i)
  
  # table names
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  post3m_table_name <- paste0("post3m_", i)
  
  # get table
  drug_merge_tablename <- drug_merge_tablename %>% analysis$cached(drug_merge_tablename)
  
  data <- drug_merge_tablename %>%
    # keep only the first instance of the drug start
    filter(druginstance==1)  %>%
    # create calculate minimum valid date for outcome: start + 91 days
    mutate(minvaliddate3m = sql("date_add(dstartdate, interval 91 day)"),
           
           # pmin gets translated to SQL LEAST which doesn't like missing values
           maxtime3m = pmin(ifelse(is.na(timetoaddrem), 122, timetoaddrem),
                            ifelse(is.na(timetochange), 122, timetochange+30), 122, na.rm=TRUE),
           
           # calculate interval between dstart 
           lastvaliddate3m=if_else(maxtime3m<91, NA, sql("date_add(dstartdate, interval maxtime3m day)"))) %>%
    
    # date of outcome must be above minimum date and below or equal to the last valid date 
    filter(date>=minvaliddate3m & date<=lastvaliddate3m) %>%
    # group by patid, dstartdate, drugclass
    group_by(patid, dstartdate, drugclass) %>%
    # create variable with time difference between outcome date and 91, select minimum difference
    mutate(min_timediff=min(abs(91-drugdatediff), na.rm=TRUE)) %>%
    # keep only the closest value to the minimum
    filter(abs(91-drugdatediff)==min_timediff) %>%
    # calculate the minimum biomarker value
    mutate(post_biomarker_3m=min(testvalue, na.rm=TRUE)) %>%
    # keep only minimum value
    filter(post_biomarker_3m==testvalue) %>%
    # rename variables
    rename(post_biomarker_3mdate=date,
           post_biomarker_3mdrugdiff=drugdatediff) %>%
    # order outcome variable by outcome biomarker
    dbplyr::window_order(post_biomarker_3mdrugdiff) %>%
    # keep only the first row for each grouping
    filter(row_number()==1) %>%
    # remove grouping
    ungroup() %>%
    # select important variables
    select(patid, dstartdate, drugclass, post_biomarker_3m, post_biomarker_3mdate, post_biomarker_3mdrugdiff) %>%
    # cache this table
    analysis$cached(post3m_table_name, indexes=c("patid", "dstartdate", "drugclass"))
  
  # rename table
  assign(post3m_table_name, data)
  
  
}



# 6 month response

for (i in biomarkers) {
  
  # print biomarker
  print(i)
  
  # table names
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  post6m_table_name <- paste0("post6m_", i)
  
  # get table
  drug_merge_tablename <- drug_merge_tablename %>% analysis$cached(drug_merge_tablename)
  
  data <- drug_merge_tablename %>%
    # keep only the first instance of the drug start
    filter(druginstance==1)  %>%
    # create calculate minimum valid date for outcome: start + 91 days
    mutate(minvaliddate6m = sql("date_add(dstartdate, interval 91 day)"),
           
           # pmin gets translated to SQL LEAST which doesn't like missing values
           maxtime6m = pmin(ifelse(is.na(timetoaddrem), 274, timetoaddrem),
                            ifelse(is.na(timetochange), 274, timetochange+91), 274, na.rm=TRUE),
           
           # calculate interval between dstart
           lastvaliddate6m=if_else(maxtime6m<91, NA, sql("date_add(dstartdate, interval maxtime6m day)"))) %>%
    
    # date of outcome must be above minimum date and below or equal to the last valid date
    filter(date>=minvaliddate6m & date<=lastvaliddate6m) %>%
    # group by patid, dstartdate, drugclass
    group_by(patid, dstartdate, drugclass) %>%
    # create variable with time difference between outcome date and 183, select minimum difference
    mutate(min_timediff=min(abs(183-drugdatediff), na.rm=TRUE)) %>%
    # keep only the closest value to the minimum
    filter(abs(183-drugdatediff)==min_timediff) %>%
    # calculate the minimum biomarker value
    mutate(post_biomarker_6m=min(testvalue, na.rm=TRUE)) %>%
    # keep only minimum value
    filter(post_biomarker_6m==testvalue) %>%
    # rename variables
    rename(post_biomarker_6mdate=date,
           post_biomarker_6mdrugdiff=drugdatediff) %>%
    # order outcome variable by outcome biomarker
    dbplyr::window_order(post_biomarker_6mdrugdiff) %>%
    # keep only the first row for each grouping
    filter(row_number()==1) %>%
    # remove grouping
    ungroup() %>%
    # select important variables
    select(patid, dstartdate, drugclass, post_biomarker_6m, post_biomarker_6mdate, post_biomarker_6mdrugdiff) %>%
    # cache this table
    analysis$cached(post6m_table_name, indexes=c("patid", "dstartdate", "drugclass"))
  
  # rename table
  assign(post6m_table_name, data)
  
}



# 12 month response

for (i in biomarkers) {
  
  # print biomarker
  print(i)
  
  # table names
  drug_merge_tablename <- paste0("full_", i, "_drug_merge")
  post12m_table_name <- paste0("post12m_", i)
  
  # get table
  drug_merge_tablename <- drug_merge_tablename %>% analysis$cached(drug_merge_tablename)
  
  data <- drug_merge_tablename %>%
    # keep only the first instance of the drug start
    filter(druginstance==1)  %>%
    # create calculate minimum valid date for outcome: start + 274 days
    mutate(minvaliddate12m = sql("date_add(dstartdate, interval 274 day)"),
           
           # pmin gets translated to SQL LEAST which doesn't like missing values
           maxtime12m = pmin(ifelse(is.na(timetoaddrem), 457, timetoaddrem),
                             ifelse(is.na(timetochange), 457, timetochange+91), 457, na.rm=TRUE),
           
           # calculate interval between dstart
           lastvaliddate12m=if_else(maxtime12m<274, NA, sql("date_add(dstartdate, interval maxtime12m day)"))) %>%
    
    # date of outcome must be above minimum date and below or equal to the last valid date
    filter(date>=minvaliddate12m & date<=lastvaliddate12m) %>%
    # group by patid, dstartdate, drugclass
    group_by(patid, dstartdate, drugclass) %>%
    # create variable with time difference between outcome date and 365, select minimum difference
    mutate(min_timediff=min(abs(365-drugdatediff), na.rm=TRUE)) %>%
    # keep only the closest value to the minimum
    filter(abs(365-drugdatediff)==min_timediff) %>%
    # calculate the minimum biomarker value
    mutate(post_biomarker_12m=min(testvalue, na.rm=TRUE)) %>%
    # keep only minimum value
    filter(post_biomarker_12m==testvalue) %>%
    # rename variables
    rename(post_biomarker_12mdate=date,
           post_biomarker_12mdrugdiff=drugdatediff) %>%
    # order outcome variable by outcome biomarker
    dbplyr::window_order(post_biomarker_12mdrugdiff) %>%
    # keep only the first row for each grouping
    filter(row_number()==1) %>%
    # remove grouping
    ungroup() %>%
    # select important variables
    select(patid, dstartdate, drugclass, post_biomarker_12m, post_biomarker_12mdate, post_biomarker_12mdrugdiff) %>%
    # cache this table
    analysis$cached(post12m_table_name, indexes=c("patid", "dstartdate", "drugclass"))
  
  # rename table
  assign(post12m_table_name, data)
  
}



# Combine with baseline values and find response

baseline_biomarkers <- baseline_biomarkers %>% analysis$cached("baseline_biomarkers")
combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop")

response_biomarkers <- baseline_biomarkers %>%
  left_join((combo_start_stop %>% select(patid, dcstartdate, timetochange, timetoaddrem, multi_drug_start, timeprevcombo)), by=c("patid","dstartdate"="dcstartdate")) %>%
  filter(druginstance==1)


for (i in biomarkers) {
  
  # print biomarker
  print(i)
  
  # table names
  post3m_table <- get(paste0("post3m_", i))
  post6m_table <- get(paste0("post6m_", i))
  post12m_table <- get(paste0("post12m_", i))
  
  # name of pre drug start biomarker variables
  pre_biomarker_variable <- as.symbol(paste0("pre", i))
  pre_biomarker_date_variable <- as.symbol(paste0("pre", i, "date"))
  pre_biomarker_drugdiff_variable <- as.symbol(paste0("pre", i, "drugdiff"))
  
  # name of outcome biomarker variables
  post_3m_biomarker_variable <- paste0("post", i, "3m")
  post_3m_biomarker_date_variable <- paste0("post", i, "3mdate")
  post_3m_biomarker_drugdiff_variable <- paste0("post", i, "3mdrugdiff")
  biomarker_3m_response_variable <- paste0(i, "resp3m")
  post_6m_biomarker_variable <- paste0("post", i, "6m")
  post_6m_biomarker_date_variable <- paste0("post", i, "6mdate")
  post_6m_biomarker_drugdiff_variable <- paste0("post", i, "6mdrugdiff")
  biomarker_6m_response_variable <- paste0(i, "resp6m")
  post_12m_biomarker_variable <- paste0("post", i, "12m")
  post_12m_biomarker_date_variable <- paste0("post", i, "12mdate")
  post_12m_biomarker_drugdiff_variable <- paste0("post", i, "12mdrugdiff")
  biomarker_12m_response_variable <- paste0(i, "resp12m")

  # interim table name to ensure caching between steps (faster compute)
  interim_response_biomarker_table <- paste0("response_biomarkers_interim_", i)
  
  # join baseline values with response values
  response_biomarkers <- response_biomarkers %>%
    left_join(post3m_table, by=c("patid", "dstartdate", "drugclass")) %>%
    left_join(post6m_table, by=c("patid", "dstartdate", "drugclass")) %>%
    left_join(post12m_table, by=c("patid", "dstartdate", "drugclass"))
  
  
  # make sure HbA1c outcome is more than 61 from previous drug combo
  if (i %in% c("hba1c", "sbp", "dbp")) {
    response_biomarkers <- response_biomarkers %>%
      mutate(post_biomarker_3m=ifelse(!is.na(timeprevcombo) & timeprevcombo<=61, NA, post_biomarker_3m),
             post_biomarker_3mdate=if_else(!is.na(timeprevcombo) & timeprevcombo<=61, as.Date(NA), post_biomarker_3mdate),
             post_biomarker_3mdrugdiff=ifelse(!is.na(timeprevcombo) & timeprevcombo<=61, NA, post_biomarker_3mdrugdiff),
        post_biomarker_6m=ifelse(!is.na(timeprevcombo) & timeprevcombo<=61, NA, post_biomarker_6m),
             post_biomarker_6mdate=if_else(!is.na(timeprevcombo) & timeprevcombo<=61, as.Date(NA), post_biomarker_6mdate),
             post_biomarker_6mdrugdiff=ifelse(!is.na(timeprevcombo) & timeprevcombo<=61, NA, post_biomarker_6mdrugdiff),
             post_biomarker_12m=ifelse(!is.na(timeprevcombo) & timeprevcombo<=61, NA, post_biomarker_12m),
             post_biomarker_12mdate=if_else(!is.na(timeprevcombo) & timeprevcombo<=61, as.Date(NA), post_biomarker_12mdate),
             post_biomarker_12mdrugdiff=ifelse(!is.na(timeprevcombo) & timeprevcombo<=61, NA, post_biomarker_12mdrugdiff))
  }
  
  response_biomarkers <- response_biomarkers %>%
    # relocate variables in the dataset
    relocate(pre_biomarker_variable, .before=post_biomarker_3m) %>%
    relocate(pre_biomarker_date_variable, .before=post_biomarker_3m) %>%
    relocate(pre_biomarker_drugdiff_variable, .before=post_biomarker_3m) %>%
    
    # calculate difference of post - prev biomarkers
    mutate({{biomarker_6m_response_variable}}:=ifelse(!is.na(pre_biomarker_variable) & !is.na(post_biomarker_6m), post_biomarker_6m-pre_biomarker_variable, NA),
           {{biomarker_12m_response_variable}}:=ifelse(!is.na(pre_biomarker_variable) & !is.na(post_biomarker_12m), post_biomarker_12m-pre_biomarker_variable, NA)) %>%
    
    # rename biomarkers to the specific biomarker being used
    rename({{post_3m_biomarker_variable}}:=post_biomarker_3m,
           {{post_3m_biomarker_date_variable}}:=post_biomarker_3mdate,
           {{post_3m_biomarker_drugdiff_variable}}:=post_biomarker_3mdrugdiff,
           {{post_6m_biomarker_variable}}:=post_biomarker_6m,
           {{post_6m_biomarker_date_variable}}:=post_biomarker_6mdate,
           {{post_6m_biomarker_drugdiff_variable}}:=post_biomarker_6mdrugdiff,
           {{post_12m_biomarker_variable}}:=post_biomarker_12m,
           {{post_12m_biomarker_date_variable}}:=post_biomarker_12mdate,
           {{post_12m_biomarker_drugdiff_variable}}:=post_biomarker_12mdrugdiff) %>%
    
    # cache this table
    analysis$cached(interim_response_biomarker_table, indexes=c("patid", "dstartdate", "drugclass"))
  
}



# Add in next eGFR measurement

analysis = cprd$analysis("all")

egfr_long <- egfr_long %>% analysis$cached("patid_clean_egfr_medcodes")

analysis = cprd$analysis("pedro_BP")

next_egfr <- baseline_biomarkers %>%
  # select important variables
  select(patid, drugclass, dstartdate, preegfrdate) %>%
  # join baseline_biomarkers with egfr medcodes
  left_join(egfr_long, by="patid") %>%
  # select egfr measures after treatment initiation
  filter(datediff(date, preegfrdate)>0) %>%
  # group by patid, drugclass and drug start date
  group_by(patid, drugclass, dstartdate) %>%
  # select the minimum measurement of egfr
  summarise(next_egfr_date=min(date, na.rm=TRUE)) %>%
  # cache this table
  analysis$cached("response_biomarkers_next_egfr", indexes=c("patid", "dstartdate", "drugclass"))


# Add in 40% decline in eGFR outcome

## Join drug start dates with all longitudinal eGFR measurements, and only keep later eGFR measurements which are <=40% of the baseline value
## Checked and those with null eGFR do get dropped
egfr40 <- baseline_biomarkers %>%
  # select important variables
  select(patid, drugclass, dstartdate, preegfr, preegfrdate) %>%
  # join baseline_biomarkers with egfr medcodes
  left_join(egfr_long, by="patid") %>%
  # select egfr measures after treatment initation and a 40% decline
  filter(datediff(date, preegfrdate)>0 & testvalue<=0.6*preegfr) %>%
  # group by patid, drugclass and dstartdate
  group_by(patid, drugclass, dstartdate) %>%
  # select minimum measurement of egfr
  summarise(egfr_40_decline_date=min(date, na.rm=TRUE)) %>%
  # cache this table
  analysis$cached("response_biomarkers_egfr40", indexes=c("patid", "dstartdate", "drugclass"))



# Join to rest of response dataset and move where height variable is
response_biomarkers <- response_biomarkers %>%
  # join post egfr measurements
  left_join(next_egfr, by=c("patid", "drugclass", "dstartdate")) %>%
  # join 40% decline in egfr
  left_join(egfr40, by=c("patid", "drugclass", "dstartdate")) %>%
  # relocate columns
  relocate(height, .after=timeprevcombo) %>%
  relocate(prehba1c12m, .after=hba1cresp12m) %>%
  relocate(prehba1c12mdate, .after=prehba1c12m) %>%
  relocate(prehba1c12mdrugdiff, .after=prehba1c12mdate) %>%
  relocate(prehba1c2yrs, .after=hba1cresp12m) %>%
  relocate(prehba1c2yrsdate, .after=prehba1c2yrs) %>%
  relocate(prehba1c2yrsdrugdiff, .after=prehba1c2yrsdate) %>%
  # cache this table
  analysis$cached("response_biomarkers", indexes=c("patid", "dstartdate", "drugclass"))

  



