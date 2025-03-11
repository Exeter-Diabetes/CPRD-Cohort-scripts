
# Adds 3 month, 6 month and 12 month discontinuation variables for all drug class periods


############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "diabetes-jun2024",cprdConf = "~/.aurum.yaml")

analysis = cprd$analysis("mm")


############################################################################################

# Bring together drug start/stop dates (from drug_start_stop), nextremdrug (from combo_start_stop) and time to last prescription (timetolastpx) from all_scripts table
## Too slow if join all_scripts on both date and patid - join with patid only and then remove rows where dstartdate!=date

drug_class_start_stop <- drug_class_start_stop %>% analysis$cached("drug_class_start_stop")
combo_class_start_stop <- combo_class_start_stop %>% analysis$cached("combo_class_start_stop")
all_scripts <- all_scripts %>% analysis$cached("all_scripts")


# Create time on drug variable
drug_class_start_stop <- drug_class_start_stop %>%
  mutate(timeondrug = datediff(dstopdate_class, dstartdate_class))


discontinuation <- drug_class_start_stop %>%
  select(patid, dstartdate_class, drugline_all, dstopdate_class, drug_class, drug_instance, timeondrug) %>%
  inner_join((combo_class_start_stop %>% select(patid, dcstartdate, nextremdrug)), by=c("patid", c("dstartdate_class"="dcstartdate"))) %>%
  inner_join((all_scripts %>% select(patid, date, timetolastpx)), by="patid") %>%
  analysis$cached("discontinuation_interim_1", indexes=c("dstartdate_class", "date"))

discontinuation <- discontinuation %>%
  filter(dstartdate_class==date) %>%
  select(-date) %>%
  analysis$cached("discontinuation_interim_2", indexes=c("patid", "dstartdate_class", "drug_class", "timeondrug", "nextremdrug", "timetolastpx"))


############################################################################################

# Add binary variables for whether drug stopped within 3/6/12 months

discontinuation <- discontinuation %>%
  mutate(ttc3m=timeondrug<=91,
         ttc6m=timeondrug<=183,
         ttc12m=timeondrug<=365)


# Make variables for whether discontinue or not
## e.g. stopdrug3m_6mFU:

### 1 if they stop drug within 3 month (ttc3m==1)
### # This includes: another diabetes med is stopped or started before the current drug is discontinued: nextremdrug==current drug
### # This includes: instances where discontinuation represents a break in the current drug before restarting: nextremdrug==NA
### 0 if they don't stop drug within 3 month (ttc3m==0)
### Missing (NA) if they stop drug within 3 month (ttc3m==1) BUT there is <= 6 months follow-up (FU) post-discontinuation to confirm discontinuation

discontinuation <- discontinuation %>%
  
  mutate(stopdrug_3m_3mFU=ifelse(ttc3m==0, 0L,
                                 ifelse(ttc3m==1 & (timetolastpx-timeondrug)>91, 1L, NA)),
         stopdrug_3m_6mFU=ifelse(ttc3m==0, 0L,
                                 ifelse(ttc3m==1 & (timetolastpx-timeondrug)>183, 1L, NA)),
         
         stopdrug_6m_3mFU=ifelse(ttc6m==0, 0L,
                                 ifelse(ttc6m==1 & (timetolastpx-timeondrug)>91, 1L, NA)),
         stopdrug_6m_6mFU=ifelse(ttc6m==0, 0L,
                                 ifelse(ttc6m==1 & (timetolastpx-timeondrug)>183, 1L, NA)),
         
         stopdrug_12m_3mFU=ifelse(ttc12m==0, 0L,
                                  ifelse(ttc12m==1 & (timetolastpx-timeondrug)>91, 1L, NA)),
         stopdrug_12m_6mFU=ifelse(ttc12m==0, 0L,
                                  ifelse(ttc12m==1 & (timetolastpx-timeondrug)>183, 1L, NA))) %>%
  
  analysis$cached("discontinuation_interim_3", indexes=c("patid", "dstartdate_class", "drug_class"))



############################################################################################

# Add in discontinuation history for each variable:
# For other drugs besides MFN: 1 if ever discontinued MFN, 0 if never discontinued MFN, NA if all discontinuation on MFN missing / never took MFN
# For MFN: NA for all
# Only include MFN periods with dstopdate prior to current dstartdate



discontinuation <- discontinuation %>%
  mutate(mfn_date=ifelse(drug_class=="MFN", dstopdate_class, dstartdate_class),
         stopdrug_3m_3mFU_MFN=ifelse(is.na(stopdrug_3m_3mFU) | drug_class!="MFN", NA,
                                     ifelse(drug_class=="MFN" & stopdrug_3m_3mFU==0, 0L, 1L)),
         stopdrug_3m_6mFU_MFN=ifelse(is.na(stopdrug_3m_6mFU) | drug_class!="MFN", NA,
                                     ifelse(drug_class=="MFN" & stopdrug_3m_6mFU==0, 0L, 1L)),
         stopdrug_6m_3mFU_MFN=ifelse(is.na(stopdrug_6m_3mFU) | drug_class!="MFN", NA,
                                     ifelse(drug_class=="MFN" & stopdrug_6m_3mFU==0, 0L, 1L)),
         stopdrug_6m_6mFU_MFN=ifelse(is.na(stopdrug_6m_6mFU) | drug_class!="MFN", NA,
                                     ifelse(drug_class=="MFN" & stopdrug_6m_6mFU==0, 0L, 1L)),
         stopdrug_12m_3mFU_MFN=ifelse(is.na(stopdrug_12m_3mFU) | drug_class!="MFN", NA,
                                      ifelse(drug_class=="MFN" & stopdrug_12m_3mFU==0, 0L, 1L)),
         stopdrug_12m_6mFU_MFN=ifelse(is.na(stopdrug_12m_6mFU) | drug_class!="MFN", NA,
                                      ifelse(drug_class=="MFN" & stopdrug_12m_6mFU==0, 0L, 1L))) %>%
  group_by(patid) %>%
  dbplyr::window_order(mfn_date) %>%
  mutate(stopdrug_3m_3mFU_MFN_hist=ifelse(drug_class=="MFN", NA, cumsum(stopdrug_3m_3mFU_MFN)),
         stopdrug_3m_6mFU_MFN_hist=ifelse(drug_class=="MFN", NA, cumsum(stopdrug_3m_6mFU_MFN)),
         stopdrug_6m_3mFU_MFN_hist=ifelse(drug_class=="MFN", NA, cumsum(stopdrug_6m_3mFU_MFN)),
         stopdrug_6m_6mFU_MFN_hist=ifelse(drug_class=="MFN", NA, cumsum(stopdrug_6m_6mFU_MFN)),
         stopdrug_12m_3mFU_MFN_hist=ifelse(drug_class=="MFN", NA, cumsum(stopdrug_12m_3mFU_MFN)),
         stopdrug_12m_6mFU_MFN_hist=ifelse(drug_class=="MFN", NA, cumsum(stopdrug_12m_6mFU_MFN))) %>%
  
  ungroup() %>%
  
  select(-c(stopdrug_3m_3mFU_MFN, stopdrug_3m_6mFU_MFN, stopdrug_6m_3mFU_MFN, stopdrug_6m_6mFU_MFN, stopdrug_12m_3mFU_MFN, stopdrug_12m_6mFU_MFN, mfn_date)) %>%
  
  analysis$cached("discontinuation", indexes=c("patid", "dstartdate_class", "drug_class"))




