
# Produces all_patid_ethnicity table

# GP ethnicity categories:
# eth16                           eth5                      QRISK2
## 1. British                     0. White                  1. White
## 2. Irish                       0. White                  1. White
## 3. Other White                 0. White                  1. White
## 4. White and Black Caribbean   4. Mixed                  9. Other
## 5. White and Black African     4. Mixed                  9. Other
## 6. White and Asian             4. Mixed                  9. Other
## 7. Other Mixed                 4. Mixed                  9. Other
## 8. Indian                      1. South Asian            2. Indian
## 9. Pakistani                   1. South Asian            3. Pakistani
## 10. Bangladeshi                1. South Asian            4. Bangladeshi
## 11. Other Asian                1. South Asian            5. Other Asian
## 12. Caribbean                  2. Black                  6. Black Caribbean
## 13. African                    2. Black                  7. Black African
## 14. Other Black                2. Black                  9. Other
## 15. Chinese                    3. Other                  8. Chinese
## 16. Other Ethnic group         3. Other                  9. Other
## 17. Not Stated/Unknown         5. Not stated/Unknown     0. Unknown


# Algorithm: https://github.com/Exeter-Diabetes/CPRD-Codelists/blob/main/readme.md#ethnicity

# Note: don't have HES ethnicity currently

############################################################################################

# Setup
.libPaths("C:/Users/rh530/OneDrive - University of Exeter/R/win-library/4.1")
library(aurum)
library(tidyverse)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote-jun24dm",cprdConf = "C:/Users/rh530/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "01/06/2024")

analysis = cprd$analysis("all_patid")


############################################################################################

# Find ethnicity from GP codes - separately for 3 different categories

## All 3 codelists (ethnicity_5cat, ethnicity_16cat and ethnicity_qrisk2) are identical, just with different category columns

raw_gp_ethnicity <- cprd$tables$observation %>% 
  inner_join(codes$ethnicity_5cat, by="medcodeid") %>%
  select(patid, obsdate, medcodeid) %>%
  analysis$cached("raw_gp_ethnicity", indexes=c("patid", "obsdate", "medcodeid"))


# 5 category GP ethnicity
gp_5cat_ethnicity <- raw_gp_ethnicity %>% 
  inner_join(codes$ethnicity_5cat, by="medcodeid") %>%

  filter(ethnicity_5cat_cat!=5) %>%                                                 # remove 'missing' codes
  
  group_by(patid, ethnicity_5cat_cat) %>%
  summarise(eth_code_count=n(),                                                     # code count per person per ethnicity category
            latest_date_per_cat=max(obsdate, na.rm=TRUE)) %>%                       
  ungroup() %>%
  
  group_by(patid) %>%
  filter(eth_code_count==max(eth_code_count, na.rm=TRUE)) %>%                       # only keep categories with most counts
  filter(n()==1 | latest_date_per_cat==max(latest_date_per_cat, na.rm=TRUE)) %>%    # keep if 1 row per person, or if on latest date
  filter(n()==1) %>%                                                                # keep if 1 row per person
  ungroup() %>% 
  
  select(patid, gp_5cat_ethnicity=ethnicity_5cat_cat) %>%
  analysis$cached("gp_5cat_ethnicity",unique_indexes="patid", indexes="gp_5cat_ethnicity")

#16 category GP ethnicity
gp_16cat_ethnicity <- raw_gp_ethnicity %>% 
  inner_join(codes$ethnicity_16cat, by="medcodeid") %>%
  
  filter(ethnicity_16cat_cat!=17) %>%                                                # remove 'missing' codes
  
  group_by(patid, ethnicity_16cat_cat) %>%
  summarise(eth_code_count=n(),                                                     # code count per person per ethnicity category
            latest_date_per_cat=max(obsdate, na.rm=TRUE)) %>%                       
  ungroup() %>%
  
  group_by(patid) %>%
  filter(eth_code_count==max(eth_code_count, na.rm=TRUE)) %>%                       # only keep categories with most counts
  filter(n()==1 | latest_date_per_cat==max(latest_date_per_cat, na.rm=TRUE)) %>%    # keep if 1 row per person, or if on latest date
  filter(n()==1) %>%                                                                # keep if 1 row per person
  ungroup() %>% 
  
  select(patid, gp_16cat_ethnicity=ethnicity_16cat_cat) %>%
  analysis$cached("gp_16cat_ethnicity",unique_indexes="patid", indexes="gp_16cat_ethnicity")

# QRISK2 ethnicity
gp_qrisk2_ethnicity <- raw_gp_ethnicity %>% 
  inner_join(codes$qrisk2_ethnicity, by="medcodeid") %>%
  
  filter(qrisk2_ethnicity_cat!=0) %>%                                               # remove 'missing' codes
  
  group_by(patid, qrisk2_ethnicity_cat) %>%
  summarise(eth_code_count=n(),                                                     # code count per person per ethnicity category
            latest_date_per_cat=max(obsdate, na.rm=TRUE)) %>%                       
  ungroup() %>%
  
  group_by(patid) %>%
  filter(eth_code_count==max(eth_code_count, na.rm=TRUE)) %>%                       # only keep categories with most counts
  filter(n()==1 | latest_date_per_cat==max(latest_date_per_cat, na.rm=TRUE)) %>%    # keep if 1 row per person, or if on latest date
  filter(n()==1) %>%                                                                # keep if 1 row per person
  ungroup() %>% 
  
  select(patid, gp_qrisk2_ethnicity=qrisk2_ethnicity_cat) %>%
  analysis$cached("gp_qrisk2_ethnicity",unique_indexes="patid", indexes="gp_qrisk2_ethnicity")


############################################################################################

# Combine all ethnicity categories

## Set 16- and QRISK-category ethnicity to missing if directly conflicts with 5-category ethnicity

ethnicity <- cprd$tables$patient %>%
  select(patid) %>%
  left_join(gp_5cat_ethnicity, by="patid") %>%
  left_join(gp_16cat_ethnicity, by="patid") %>%
  left_join(gp_qrisk2_ethnicity, by="patid") %>%
  
  mutate(gp_16cat_ethnicity=ifelse((gp_5cat_ethnicity==0 & (gp_16cat_ethnicity==8 | gp_16cat_ethnicity==9 | gp_16cat_ethnicity==10 | gp_16cat_ethnicity==11 | gp_16cat_ethnicity==12 | gp_16cat_ethnicity==13 | gp_16cat_ethnicity==14 | gp_16cat_ethnicity==15)) |
         (gp_5cat_ethnicity==1 & (gp_16cat_ethnicity==1 | gp_16cat_ethnicity==2 | gp_16cat_ethnicity==3 | gp_16cat_ethnicity==4 | gp_16cat_ethnicity==5 | gp_16cat_ethnicity==12 | gp_16cat_ethnicity==13 | gp_16cat_ethnicity==14 | gp_16cat_ethnicity==15)) |
         (gp_5cat_ethnicity==2 & (gp_16cat_ethnicity==1 | gp_16cat_ethnicity==2 | gp_16cat_ethnicity==3 | gp_16cat_ethnicity==6 | gp_16cat_ethnicity==8 | gp_16cat_ethnicity==9 | gp_16cat_ethnicity==10 | gp_16cat_ethnicity==11 | gp_16cat_ethnicity==15)), NA, gp_16cat_ethnicity),
         
         gp_qrisk2_ethnicity=ifelse((gp_5cat_ethnicity==0 & (gp_qrisk2_ethnicity==2 | gp_qrisk2_ethnicity==3 | gp_qrisk2_ethnicity==4 | gp_qrisk2_ethnicity==5 | gp_qrisk2_ethnicity==6 | gp_qrisk2_ethnicity==7 | gp_qrisk2_ethnicity==8)) |
(gp_5cat_ethnicity==1 & (gp_qrisk2_ethnicity==1 | gp_qrisk2_ethnicity==6 | gp_qrisk2_ethnicity==7 | gp_qrisk2_ethnicity==8)) |
(gp_5cat_ethnicity==2 & (gp_qrisk2_ethnicity==1 | gp_qrisk2_ethnicity==2 | gp_qrisk2_ethnicity==3 | gp_qrisk2_ethnicity==4 | gp_qrisk2_ethnicity==5 | gp_qrisk2_ethnicity==8)), NA, gp_qrisk2_ethnicity)) %>%
  
  mutate(gp_qrisk2_ethnicity=ifelse(is.na(gp_qrisk2_ethnicity), 0L, gp_qrisk2_ethnicity)) %>%
  
  select(patid, ethnicity_5cat = gp_5cat_ethnicity, ethnicity_16cat = gp_16cat_ethnicity, ethnicity_qrisk2 = gp_qrisk2_ethnicity) %>%
  
  analysis$cached("ethnicity", unique_indexes="patid")

