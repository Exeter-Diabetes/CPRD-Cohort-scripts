
# Processes prescriptions to find start and stop dates for drugs, and when other drug classes added or remove relative to start date for drug class of interest
# This file is for 90 day gap between prescriptions
############################################################################################

# Setup
library(tidyverse)
library(aurum)
rm(list=ls())

cprd = CPRDData$new(cprdEnv = "test-remote",cprdConf = "~/.aurum.yaml")
codesets = cprd$codesets()
codes = codesets$getAllCodeSetVersion(v = "31/10/2021")

############################################################################################

# Define drug classes

meds <- c("ace_inhibitors",
          "arb",
          "calcium_channel_blockers",
          "thiazide_diuretics")

############################################################################################

# # Get pre-existing drug tables for select meds 
# 
# analysis = cprd$analysis("all_patid")
# 
# raw_ace_inhibitors_prodcodes <- raw_ace_inhibitors_prodcodes %>% analysis$cached("raw_ace_inhibitors_prodcodes")
# raw_arb_prodcodes <- raw_arb_prodcodes %>% analysis$cached("raw_arb_prodcodes")
# raw_calcium_channel_blockers_prodcodes <- raw_calcium_channel_blockers_prodcodes %>% analysis$cached("raw_calcium_channel_blockers_prodcodes")
# raw_thiazide_diuretics_prodcodes <- raw_thiazide_diuretics_prodcodes %>% analysis$cached("raw_thiazide_diuretics_prodcodes")


# Instead of getting pre-existing, create our own with dosage indications


analysis = cprd$analysis("pedro_BP")

# iterate through each medication
for (i in meds) {
  
  print(i)
  
  raw_tablename <- paste0("raw_", i, "_prodcodes")
  
  # take the original table of drug issues
  data <- cprd$tables$drugIssue %>%
    # select the columns needed
    select(patid, prodcodeid, dosageid, quantity, duration, date = issuedate) %>%
    # inner join codes for ACE medication (inner join so that we only keep the interesting codes)
    inner_join(codes[[i]] %>%
                 mutate(drugclass = i) %>%
                 select(prodcodeid, drugclass), by = "prodcodeid") %>%
    # remove variables
    select(-prodcodeid) %>%
    # cache this table
    analysis$cached(raw_tablename, indexes = c("patid", "date"))
  
  # give that table the assigned name
  assign(raw_tablename, data)
  
}


############################################################################################

# Clean scripts (remove if before DOB or after lcd/deregistration/death), 

analysis = cprd$analysis("pedro_BP")

# iterate through each medication
for (i in meds) {
  
  print(i)
  
  raw_tablename <- paste0("raw_", i, "_prodcodes")
  clean_tablename <- paste0("clean_", i, "_prodcodes")
  
  
  data <- get(raw_tablename) %>%
    # inner join valid date lookup tables to exclude values that shouldn't be analysed
    inner_join(cprd$tables$validDateLookup %>%
                 # select the right variables
                 select(patid, min_dob, gp_ons_end_date), by = "patid") %>%
    # filter out the values that should be removed
    filter(date>=min_dob & date<=gp_ons_end_date) %>%
    # remove variables
    select(-min_dob, -gp_ons_end_date) %>%
    # cache this table
    analysis$cached(clean_tablename, indexes = c("patid", "date"))
  
  assign(clean_tablename, data)
  
}


############################################################################################

# Remove patid/date duplicates and make new summary coverage for each drug class

# Replace quantity, daily dose and duration with mean grouped by patid/date (first we have to join with dosageid lookup to get daily dose)

analysis = cprd$analysis("pedro_BP")

# iterate through each medication
for (i in meds) {
  
  print(i)
  
  clean_tablename <- paste0("clean_", i, "_prodcodes")
  clean_dosage_tablename <- paste0("clean_dosage_", i, "_prodcodes")
  
  data <- get(clean_tablename) %>%
    # left join the common Dose code table by dosageid
    left_join(cprd$tables$commonDose, by = "dosageid") %>%
    # group by patid/date
    group_by(patid, date) %>%
    # edit quantiy / daily_dose / duration
    mutate(
      quantity = mean(quantity[quantity > 0], na.rm = TRUE),
      daily_dose = mean(daily_dose[daily_dose > 0], na.rm = TRUE),
      duration = mean(duration[duration > 0], na.rm = TRUE)
    ) %>%
    # remove grouping
    ungroup() %>%
    # cache this table
    analysis$cached(clean_dosage_tablename, indexes = c("patid", "date"))
  
  assign(clean_dosage_tablename, data)
  
}

# Removing patid / date duplicates and add coverage

# iterate through each medication
for (i in meds) {
  
  print(i)
  
  clean_dosage_tablename <- paste0("clean_dosage_", i, "_prodcodes")
  clean_final_tablename <- paste0("clean_final_", i, "_prodcodes")
  
  data <- get(clean_dosage_tablename) %>%
    # group by patid / date
    group_by(patid, date) %>%
    # only keep the first instance of each one (since we already made them the same based on the code before)
    ## row_number is a function that counts the rows
    filter(row_number()==1) %>%
    # remove grouping
    ungroup() %>%
    # Add coverage = quantity/daily dose where both available, otherwise = duration
    mutate(coverage = ifelse(!is.na(quantity) & !is.na(daily_dose), quantity/daily_dose, duration)) %>%
    # cache this table
    analysis$cached(clean_final_tablename, indexes = c("patid", "date"))
  
  assign(clean_final_tablename, data)
  
}


############################################################################################

# all_scripts = 1 line per patid / date where script issued, with drug class info in wide format

analysis = cprd$analysis("pedro_BP")

# start with ACEi prescriptions
all_scripts_long_interim_1 <- clean_final_ace_inhibitors_prodcodes %>%
  # select only the columns necessary
  select(patid, date, drugclass, quantity, daily_dose, duration, coverage) %>%
  # join ARB prescriptions below
  union_all(
    clean_final_arb_prodcodes %>%
      # select only the columns necessary
      select(patid, date, drugclass, quantity, daily_dose, duration, coverage)
  ) %>%
  # join CCB prescriptions below
  union_all(
    clean_final_calcium_channel_blockers_prodcodes %>%
      # select only the columns necessary
      select(patid, date, drugclass, quantity, daily_dose, duration, coverage)
  ) %>%
  # join TZD prescriptions below
  union_all(
    clean_final_thiazide_diuretics_prodcodes %>%
      # select only the columns necessary
      select(patid, date, drugclass, quantity, daily_dose, duration, coverage)
  ) %>%
  # cache this table
  analysis$cached("all_scripts_long_interim_1", indexes = c("patid", "date"))


# Define whether date is start or stop for each drug class
## Find time from previous script (dprevuse) and to next script (dnextuse) for same person and same drug class
## If no previous script/previous script more than 3 months (90 days) earlier, define as start date (dstart = 1)
## If no next script/next script more than 3 months (90 days) later, define as stop date (dstop = 1)

all_scripts_long_interim_2 <- all_scripts_long_interim_1 %>%
  # group by patid and drugclass
  group_by(patid, drugclass) %>%
  # dates in increasing order
  dbplyr::window_order(date) %>%
  # create variables for used for start and stop of therapies
  mutate(
    dnextuse=datediff(lead(date), date),
    dprevuse=datediff(date, lag(date)),
    dstart=dprevuse>90 | is.na(dprevuse),
    dstop=dnextuse>90 | is.na(dnextuse)
  ) %>%
  # remove grouping
  ungroup() %>%
  # cache this table
  analysis$cached("all_scripts_long_interim_2", indexes = c("patid", "date"))


# Define number of drug classes prescribed (numpxdate), started (numstart) and stopped on each date (numstop)

all_scripts_long <- all_scripts_long_interim_2 %>%
  # group by patid and date
  group_by(patid, date) %>%
  # create variable for treatments started and stopped at each date
  mutate(
    numpxdate=n(),
    numstart=sum(dstart, na.rm=TRUE),
    numstop=sum(dstop, na.rm=TRUE)
  ) %>%
  # remove grouping
  ungroup() %>%
  # cache this table
  analysis$cached("all_scripts_long", indexes = c("patid", "date"))


# Reshape wide by drug class - so 1 row per patid/date

all_scripts_interim_1 <- all_scripts_long %>%
  # pivot the dataset into wide mode
  pivot_wider(
    # variables which we want to keep consistent for each row
    id_cols = c(patid, date, numpxdate, numstart, numstop),
    # variable that we want to be used as variable naming
    names_from = drugclass,
    # variables that we want to be created with drugclass appended
    values_from = c(dstart, dstop, coverage),
    # specify we don't want things being filled in when there is missingness
    values_fill = list(dstart = FALSE, dstop = FALSE)
  ) %>%
  # cache this table
  analysis$cached("all_scripts_interim_1", indexes = c("patid", "date"))


# Use numstart and numstop to work out total number of drug classes patient is on at each date (numdrugs; they can be on a drug even if not prescribed on that date)
## Add numstop to numdrugs so that drug stopped is included in numdrugs count on the date it is stopped

all_scripts_interim_2 <- all_scripts_interim_1 %>%
  # group by patid
  group_by(patid) %>%
  # order by date
  dbplyr::window_order(date) %>%
  # create variable for understanding the number of variables
  mutate(
    cu_numstart=cumsum(numstart),
    cu_numstop=cumsum(numstop),
    numdrugs=cu_numstart-cu_numstop+numstop
  ) %>%
  # remove grouping
  ungroup() %>%
  # cache this table
  analysis$cached("all_scripts_interim_2", indexes = c("patid", "date"))


# Make variable for what combination of drugs patient is on at each date
## First make binary variables for each drug for whether patient was on the drug (whether or not prescribed) at each date

all_scripts_interim_3 <- all_scripts_interim_2 %>%
  # group by patid
  group_by(patid) %>%
  # order by date
  dbplyr::window_order(date) %>%
  # create variables needed for drug combinations
  mutate(
    ace_inhibitors = cumsum(dstart_ace_inhibitors) > cumsum(dstop_ace_inhibitors) | dstart_ace_inhibitors == 1 | dstop_ace_inhibitors == 1,
    arb = cumsum(dstart_arb) > cumsum(dstop_arb) | dstart_arb == 1 | dstop_arb == 1,
    thiazide_diuretics = cumsum(dstart_thiazide_diuretics) > cumsum(dstop_thiazide_diuretics) | dstart_thiazide_diuretics == 1 | dstop_thiazide_diuretics == 1,
    calcium_channel_blockers = cumsum(dstart_calcium_channel_blockers) > cumsum(dstop_calcium_channel_blockers) | dstart_calcium_channel_blockers == 1 | dstop_calcium_channel_blockers == 1
  ) %>%
  # remove grouping
  ungroup() %>% 
  # cache this table
  analysis$cached("all_scripts_interim_3", indexes = c("patid", "date"))


## Use binary drug class columns to make single 'drugcombo' column with the names of all the drug classes patient is on at each date

all_scripts_interim_4 <- all_scripts_interim_3 %>%
  # remove columns about drug start (dstart) and drug stop (dstop)
  select(-c(starts_with("dstart"), starts_with("dstop"))) %>%
  # create drug combo variable
  mutate(
    # add drug info if it is being taken
    drugcombo = paste0(ifelse(ace_inhibitors == 1, "ACE_", NA),
                       ifelse(arb == 1, "ARB_", NA),
                       ifelse(thiazide_diuretics == 1, "TZD_", NA),
                       ifelse(calcium_channel_blockers == 1, "CCB_", NA)),
    # remove last hyphen if there is one
    drugcombo=ifelse(str_sub(drugcombo, -1, -1)=="_", str_sub(drugcombo, 1, -2), drugcombo)) %>%
  # cache this table
  analysis$cached("all_scripts_interim_4", indexes = c("patid", "date"))


# Recalculate numdrugs (number of different drug classes patient is on at each date) and check it matches earlier calculation

all_scripts_interim_5 <- all_scripts_interim_4 %>%
  # create numdrugs replication
  mutate(numdrugs2= ace_inhibitors + arb + thiazide_diuretics + calcium_channel_blockers) %>% 
  # cache this table
  analysis$cached("all_scripts_interim_5", indexes=c("patid", "date", "drugcombo"))

# all_scripts_interim_5 %>% filter(numdrugs!=numdrugs2 | (is.na(numdrugs) & !is.na(numdrugs2)) | (!is.na(numdrugs) & is.na(numdrugs2))) %>% count()
# 0 - perfect


# Define whether date is start or stop for each drug combination
## Coded differently to drug classes as patient can only be on one combination at once 
## Find time from previous script (dcprevuse) and to next script (dncextuse) for same person and same drug combo
## If previous script is for a different drug combo or no previous script, define as start date (dcstart=1)
## If next script is for a different drug combo or no next script, define as stop date (dcstop=1)

all_scripts_interim_6 <- all_scripts_interim_5 %>%
  # group by patid and drugcombo
  group_by(patid, drugcombo) %>%
  # order by date
  dbplyr::window_order(date) %>%
  # create variables needed
  mutate(
    dcnextuse=datediff(lead(date), date),
    dcprevuse=datediff(date, lag(date))
  ) %>%
  # remove grouping
  ungroup() %>%
  # group by patid
  group_by(patid) %>%
  # order by date
  dbplyr::window_order(date) %>%
  # create variable needed
  mutate(
    dcstart=drugcombo!=lag(drugcombo) | is.na(dcprevuse),
    dcstop=drugcombo!=lead(drugcombo) | is.na(dcnextuse)
  ) %>%
  # remove grouping
  ungroup() %>%
  # cache this table
  analysis$cached("all_scripts_interim_6", indexes=c("patid", "date", "drugcombo"))


# Add 'gaps': defined as break of >3 months (90 days) in prescribing of combination
## Update start and stop dates based on these
# Add in time to last prescription date for each patient (any drug class)

all_scripts <- all_scripts_interim_6 %>%
  # group by patid
  group_by(patid) %>%
  # order by date
  dbplyr::window_order(date) %>%
  # create variable needed
  mutate(
    stopgap=ifelse(dcnextuse>90 & drugcombo==lead(drugcombo), 1L, NA),
    startgap=ifelse((dcprevuse>90 | is.na(dcprevuse)), 1L, NA),
    dcstop=ifelse(!is.na(stopgap) & stopgap==1 & dcstop==0, 1L, dcstop),
    dcstart=ifelse(!is.na(startgap) & startgap==1 & dcstart==0, 1L, dcstart)
  ) %>%
  # remove grouping
  ungroup() %>%
  # group by patid
  group_by(patid) %>%
  # crete variable needed
  mutate(
    timetolastpx=datediff(max(date, na.rm=TRUE), date)
  ) %>%
  # remove grouping
  ungroup() %>%
  # cache this table
  analysis$cached("all_scripts", indexes=c("patid", "date", "drugcombo"))


############################################################################################

# drug_start_stop = 1 line per patid / drug class instance (continuous period of drug use)

# Just keep dates where a drug is started or stopped
## Pull out start and stop dates on rows where dstart==1
## Each row either has both start and stop date, or start on one date and next date for same patid and drug class will be stop date

drug_start_stop_interim_1 <- all_scripts_long %>%
  # filter rows with drug start and drug stop
  filter(dstart==1 | dstop==1) %>%
  # group by patid and drugclass
  group_by(patid, drugclass) %>%
  # order by date
  dbplyr::window_order(date) %>%
  # create variable needed
  mutate(
    dstartdate=if_else(dstart==1, date, as.Date(NA)),
    dstopdate=if_else(dstart==1 & dstop==1, date, 
                      if_else(dstart==1 & dstop==0, lead(date), as.Date(NA))),
    int_stopdatepluscov=sql("date_add(date, interval coverage day)"),
    dstopdatepluscov=if_else(dstart==1 & dstop==1, int_stopdatepluscov,
                             if_else(dstart==1 & dstop==0, lead(int_stopdatepluscov), as.Date(NA)))
  ) %>%
  # remove grouping
  ungroup() %>%
  # cache this table
  analysis$cached("drug_start_stop_interim_1", indexes=c("patid", "date"))


# Just keep rows where dstart==1 - 1 row per drug instance, and only keep variables which apply to whole instance, not those relating to specific scripts within the instance
# Define time on drug

drug_start_stop_interim_2 <- drug_start_stop_interim_1 %>%
  # filter rows with drug start
  filter(dstart==1) %>%
  # select the variables needed
  select(patid, drugclass, dstartdate, dstopdate, dstopdatepluscov) %>%
  # create the variables needed
  mutate(
    timeondrug=datediff(dstopdate, dstartdate),
    timeondrugpluscov=datediff(dstopdatepluscov, dstartdate)
  ) %>%
  # cache this table
  analysis$cached("drug_start_stop_interim_2", indexes=c("patid", "dstartdate"))


# Add drug order count within each patid: how many periods of medication have they had
## If multiple meds started on same day, use minimum for both/all drugs

drug_start_stop_interim_3 <- drug_start_stop_interim_2 %>%
  # group by patid
  group_by(patid) %>%
  # order by date of drug start
  dbplyr::window_order(dstartdate) %>%
  # create variable needed
  mutate(
    drugorder=row_number()
  ) %>%
  # remove grouping
  ungroup() %>%
  # group by patid and date of drug start
  group_by(patid, dstartdate) %>%
  # create variable needed
  mutate(
    drugorder=min(drugorder, na.rm=TRUE)
  ) %>%
  # remove grouping
  ungroup() %>% 
  # cache this table
  analysis$cached("drug_start_stop_interim_3", indexes=c("patid", "dstartdate"))


# Add drug instance count for each patid / drug class instance e.g. if several periods of MFN usage, these should be labelled 1, 2 etc. based on start date

drug_start_stop_interim_4 <- drug_start_stop_interim_3 %>%
  # group by patid and drugclass
  group_by(patid, drugclass) %>%
  # order by date of drug start
  dbplyr::window_order(dstartdate) %>%
  # create variable needed
  mutate(
    druginstance=row_number()
  ) %>%
  # removing group
  ungroup() %>%
  # cache this table
  analysis$cached("drug_start_stop_interim_4", indexes=c("patid", "dstartdate"))


# Add drug line for each patid / drug class: on first usage of this drug, how many previous distinct drug classes had been used + 1 
## If multiple meds started on same day, use minimum for both/all drugs

drug_line <- drug_start_stop_interim_4 %>%
  # keep only the first initiation of the therapy
  filter(druginstance==1) %>%   # same as just keeping 1 row per patid/ drug class with minimum start date
  # group by patid
  group_by(patid) %>%
  # order by date of drug start
  dbplyr::window_order(dstartdate) %>%
  # create variable needed
  mutate(
    drugline_all=row_number()
  ) %>%
  # remove grouping
  ungroup() %>%
  # group by patid and date of drug start
  group_by(patid, dstartdate) %>%
  # create variable needed
  mutate(
    drugline_all=min(drugline_all, na.rm=TRUE)
  ) %>%
  # remove grouping
  ungroup() %>%
  # select variables needed
  select(patid, drugclass, drugline_all) 

drug_start_stop <- drug_start_stop_interim_4 %>%
  # join drugline information (inner join to keep those with all information)
  inner_join(drug_line, by=c("patid", "drugclass")) %>%
  # cache this table
  analysis$cached("drug_start_stop", indexes=c("patid", "dstartdate", "drugclass", "druginstance"))



############################################################################################

# combo_start_stop = 1 line per patid / drug combo instance (continuous period of drug combo use)

# Similar process to that for drug classes above:
## Just keep dates where a drug is started or stopped
## Pull out start and stop dates on rows where dcstart==1
## Each row either has both start and stop date, or start on one date and next date for same patid will be stop date (as can only be on one drug combo at once)

combo_start_stop <- all_scripts %>%
  # keep only entries with drugcombo start and drugcombo stop
  filter(dcstart==1 | dcstop==1) %>%
  # group by patid
  group_by(patid) %>%
  # order by date
  dbplyr::window_order(date) %>%
  # create variable needed
  mutate(
    dcstartdate=if_else(dcstart==1, date, as.Date(NA)),
    dcstopdate=if_else(dcstart==1 & dcstop==1, date, 
                       if_else(dcstart==1 & dcstop==0, lead(date), as.Date(NA)))
  ) %>%
  # remove grouping
  ungroup() %>%
  # cache this table
  analysis$cached("combo_start_stop_interim_1")


# Just keep rows where dcstart==1 - 1 row per drug combo instance, and only keep variables which apply to whole instance

combo_start_stop <- combo_start_stop %>%
  # keep only drugcombo start
  filter(dcstart==1) %>%
  # select variables needed
  select(patid, all_of(meds), drugcombo, numdrugs, dcstartdate, dcstopdate)


# Add drugcomborder count within each patid: how many periods of medication have they had
## Also add 'nextdcdate': date next combination started (use stop date if last combination before end of prescriptions)

combo_start_stop <- combo_start_stop %>%
  # group by patid
  group_by(patid) %>%
  # order by drugcombo date of drug start
  dbplyr::window_order(dcstartdate) %>%
  # create variables needed
  mutate(
    drugcomboorder=row_number(),
    nextdcdate=if_else(is.na(lead(dcstartdate)), dcstopdate, lead(dcstartdate))
  ) %>%
  # remove grouping
  ungroup()


# Define what current and next drug combination represents in terms of adding/removing/swapping

combo_start_stop <- combo_start_stop %>%
  # add empty variables for these details
  mutate(add=0L,
         adddrug=NA,
         rem=0L,
         remdrug=NA,
         nextadd=0L,
         nextadddrug=NA,
         nextrem=0L,
         nextremdrug=NA
  )

# iterate through each medicine
for (i in meds) {
  
  # name of the variable being used at each iteration
  drug_col <- as.symbol(i)
  
  combo_start_stop <- combo_start_stop %>%
    # group by patid
    group_by(patid) %>%
    # order by drug combo order
    dbplyr::window_order(drugcomboorder) %>%
    # create variables needed
    mutate(
      add=ifelse(drug_col==1 & !is.na(lag(drug_col)) & lag(drug_col)==0, add+1L, add),
      adddrug=ifelse(drug_col==1 & !is.na(lag(drug_col)) & lag(drug_col)==0,
                     ifelse(is.na(adddrug), i, paste(adddrug, "&", i)), adddrug),
      
      rem=ifelse(drug_col==0 & !is.na(lag(drug_col)) & lag(drug_col)==1, rem+1L, rem),
      remdrug=ifelse(drug_col==0 & !is.na(lag(drug_col)) & lag(drug_col)==1, ifelse(is.na(remdrug), i, paste(remdrug, "&", i)), remdrug),
      
      nextrem=ifelse(drug_col==1 & !is.na(lead(drug_col)) & lead(drug_col)==0, nextrem+1L, nextrem),
      nextremdrug=ifelse(drug_col==1 & !is.na(lead(drug_col)) & lead(drug_col)==0, ifelse(is.na(nextremdrug), i, paste(nextremdrug, "&", i)), nextremdrug),
      
      nextadd=ifelse(drug_col==0 & !is.na(lead(drug_col)) & lead(drug_col)==1, nextadd+1L, nextadd),
      nextadddrug=ifelse(drug_col==0 & !is.na(lead(drug_col)) & lead(drug_col)==1, ifelse(is.na(nextadddrug), i, paste(nextadddrug, "&", i)), nextadddrug)
    ) %>%
    # remove grouping
    ungroup()
}

# cache this table
combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop_interim_2", indexes=c("patid", "dcstartdate"))


# finish last things
combo_start_stop <- combo_start_stop %>%
  # create variables needed
  mutate(
    swap=add>=1 & rem>=1,
    nextswap=nextadd>=1 & nextrem>=1,
    
    drugchange=case_when(
      add>=1 & rem==0 ~ "add",
      add==0 & rem>=1 ~ "remove",
      add>=1 & rem>=1 ~ "swap",
      add==0 & rem==0 & drugcomboorder==1 ~ "start of px",
      add==0 & rem==0 & drugcomboorder!=1  ~ "stop - break"),
    
    nextdrugchange=case_when(
      nextadd>=1 & nextrem==0 ~ "add",
      nextadd==0 & nextrem>=1 ~ "remove",
      nextadd>=1 & nextrem>=1 ~ "swap",
      nextadd==0 & nextrem==0 & nextdcdate!=dcstopdate ~ "stop - break",
      nextadd==0 & nextrem==0 & nextdcdate==dcstopdate ~ "stop - end of px")
  )



# Add time until next drug combination (if last combination or before break, use stop date of current combination), time until a different drug class added or removed, and time since previous combination prescribed, as well as date of next drug combo

combo_start_stop <- combo_start_stop %>%
  # group by patid
  group_by(patid) %>%
  # order by drugcombo start date
  dbplyr::window_order(dcstartdate) %>%
  # create variables needed
  mutate(
    timetochange=ifelse(is.na(lead(dcstartdate)) | datediff(lead(dcstartdate),dcstopdate)>90, datediff(dcstopdate, dcstartdate), datediff(lead(dcstartdate), dcstartdate)),
    timetoaddrem=ifelse(is.na(lead(dcstartdate)), NA, datediff(lead(dcstartdate), dcstartdate)),
    timeprevcombo=datediff(dcstartdate, lag(dcstartdate))
  ) %>%
  # remove grouping
  ungroup()


# Add variable to indicate whether multiple drug classes started on the same day
## Updated 28/03/2023 as realised this is missing if no prior drug periods

combo_start_stop <- combo_start_stop %>%
  # create variable needed
  mutate(
    multi_drug_start=ifelse(add>1 | (drugcomboorder==1 & numdrugs>1), 1L, 0L)
  )


# Cache

combo_start_stop <- combo_start_stop %>% analysis$cached("combo_start_stop", indexes=c("patid", "dcstartdate"))




