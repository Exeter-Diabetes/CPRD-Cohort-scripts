
# Extracts dates for alcohol consumption code occurrences in GP records

# Merges with index dates (diagnosis dates)

# Defines alcohol status at index date according to our algorithm, described here: https://github.com/Exeter-Diabetes/CPRD-Codelists#alcohol-consumption


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

analysis = cprd$analysis("at_diag")


############################################################################################

# Pull out all raw code instances and cache with 'all_patid' prefix

analysis = cprd$analysis("all_patid")

raw_alcohol_medcodes <- cprd$tables$observation %>%
  inner_join(codes$alcohol, by="medcodeid") %>%
  analysis$cached("raw_alcohol_medcodes", indexes=c("patid", "obsdate"))


############################################################################################

# Clean: remove if before DOB or after lcd/deregistration/death, and re-cache

clean_alcohol_medcodes <- raw_alcohol_medcodes %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_ons_end_date) %>%
  select(patid, date=obsdate, alcohol_cat) %>%
  distinct() %>%
  analysis$cached("clean_alcohol_medcodes", indexes=c("patid", "date", "alcohol_cat"))


############################################################################################

# Find alcohol status according to algorithm at index dates

## Get index dates (diagnosis dates)

analysis = cprd$analysis("all")

diabetes_cohort <- diabetes_cohort %>% analysis$cached("diabetes_cohort")

index_dates <- diabetes_cohort %>%
  filter(!is.na(dm_diag_date)) %>%
  select(patid, index_date=dm_diag_date)


## Join with alcohol codes on patid and retain codes before index date or up to 7 days after

analysis = cprd$analysis("at_diag")

pre_index_date_alcohol_codes <- index_dates %>%
  inner_join(clean_alcohol_medcodes, by="patid") %>%
  filter(datediff(date, index_date)<=7) %>%
  analysis$cached("pre_index_date_alcohol_merge", indexes=c("patid", "alcohol_cat"))

## Find if ever previously a 'harmful' drinker (category 3)
harmful_drinker_ever <- pre_index_date_alcohol_codes %>%
  filter(alcohol_cat=="AlcoholConsumptionLevel3") %>%
  distinct(patid) %>%
  mutate(harmful_drinker_ever=1L)

## Find most recent code
### If different categories on same day, use highest
most_recent_code <- pre_index_date_alcohol_codes %>%
  mutate(alcohol_cat_numeric = ifelse(alcohol_cat=="AlcoholConsumptionLevel0", 0L,
                                      ifelse(alcohol_cat=="AlcoholConsumptionLevel1", 1L,
                                             ifelse(alcohol_cat=="AlcoholConsumptionLevel2", 2L,
                                                    ifelse(alcohol_cat=="AlcoholConsumptionLevel3", 3L, NA))))) %>%
  group_by(patid) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  filter(alcohol_cat_numeric==max(alcohol_cat_numeric, na.rm=TRUE)) %>%
  ungroup() %>%
  analysis$cached("alcohol_interim_1", unique_indexes="patid")
    
## Pull together
alcohol_cat <- index_dates %>%
  left_join(harmful_drinker_ever, by="patid") %>%
  left_join(most_recent_code, by="patid") %>%
  mutate(alcohol_cat_numeric=ifelse(!is.na(harmful_drinker_ever) & harmful_drinker_ever==1, 3L, alcohol_cat_numeric),
         
         alcohol_cat=case_when(
           alcohol_cat_numeric==0 ~ "None",
           alcohol_cat_numeric==1 ~ "Within limits",
           alcohol_cat_numeric==2 ~ "Excess",
           alcohol_cat_numeric==3 ~ "Harmful"
         )) %>%
  select(patid, alcohol_cat) %>%
  analysis$cached("alcohol", unique_indexes="patid")
  
