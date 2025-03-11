
# Extracts dates for alcohol consumption code occurrences in GP records

# Merges with drug start and stop dates

# Defines alcohol status at drug start according to our algorithm, described here: https://github.com/Exeter-Diabetes/CPRD-Codelists#alcohol-consumption


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024", cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v="01/06/2024")

analysis = cprd$analysis("mm")


############################################################################################

# Pull out all raw code instances and cache with 'all_patid' prefix

analysis = cprd$analysis("all_patid")

raw_alcohol_medcodes <- cprd$tables$observation %>%
  inner_join(codes$alcohol, by="medcodeid") %>%
  analysis$cached("raw_alcohol_medcodes", indexes=c("patid", "obsdate"))


############################################################################################

# Clean: remove if before DOB or after lcd/deregistration, and re-cache

clean_alcohol_medcodes <- raw_alcohol_medcodes %>%
  inner_join(cprd$tables$validDateLookup, by="patid") %>%
  filter(obsdate>=min_dob & obsdate<=gp_end_date) %>%
  select(patid, date=obsdate, alcohol_cat) %>%
  distinct() %>%
  analysis$cached("clean_alcohol_medcodes", indexes=c("patid", "date", "alcohol_cat"))


############################################################################################

# Find alcohol status according to algorithm at drug start dates

# Get drug start dates
analysis = cprd$analysis("mm")
drug_start_stop <- drug_start_stop %>% analysis$cached("drug_start_stop")

# Join with alcohol codes on patid and retain codes before drug start date or up to 7 days after
predrug_alcohol_codes <- drug_start_stop %>%
  select(patid, dstartdate, drug_class, drug_substance, drug_instance) %>%
  inner_join(clean_alcohol_medcodes, by="patid") %>%
  filter(datediff(date, dstartdate)<=7) %>%
  analysis$cached("predrug_alcohol_merge", indexes=c("patid", "dstartdate", "drug_class", "drug_substance", "alcohol_cat"))

## Find if ever previously a 'harmful' drinker (category 3)
harmful_drinker_ever <- predrug_alcohol_codes %>%
  filter(alcohol_cat=="AlcoholConsumptionLevel3") %>%
  distinct(patid, dstartdate, drug_substance) %>%
  mutate(harmful_drinker_ever=1L)

## Find most recent code
### If different categories on same day, use highest
most_recent_code <- predrug_alcohol_codes %>%
  distinct(patid, dstartdate, drug_substance, date, alcohol_cat) %>%
  mutate(alcohol_cat_numeric = ifelse(alcohol_cat=="AlcoholConsumptionLevel0", 0L,
                                      ifelse(alcohol_cat=="AlcoholConsumptionLevel1", 1L,
                                             ifelse(alcohol_cat=="AlcoholConsumptionLevel2", 2L,
                                                    ifelse(alcohol_cat=="AlcoholConsumptionLevel3", 3L, NA))))) %>%
  group_by(patid, dstartdate, drug_substance) %>%
  filter(date==max(date, na.rm=TRUE)) %>%
  filter(alcohol_cat_numeric==max(alcohol_cat_numeric, na.rm=TRUE)) %>%
  ungroup() %>%
  select(-date) %>%
  analysis$cached("alcohol_interim", indexes=c("patid", "dstartdate", "drug_substance"))

## Pull together
alcohol_cat <- drug_start_stop %>%
  distinct(patid, dstartdate, drug_class, drug_substance, drug_instance) %>%
  left_join(harmful_drinker_ever, by=c("patid", "dstartdate", "drug_substance")) %>%
  left_join(most_recent_code, by = c("patid", "dstartdate", "drug_substance")) %>%
  mutate(alcohol_cat_numeric=ifelse(!is.na(harmful_drinker_ever) & harmful_drinker_ever==1, 3L, alcohol_cat_numeric),
         
         alcohol_cat=case_when(
           alcohol_cat_numeric==0 ~ "None",
           alcohol_cat_numeric==1 ~ "Within limits",
           alcohol_cat_numeric==2 ~ "Excess",
           alcohol_cat_numeric==3 ~ "Harmful"
         )) %>%
  select(-c(alcohol_cat_numeric, harmful_drinker_ever)) %>%
  analysis$cached("alcohol",indexes= c("patid", "dstartdate", "drug_substance"))

