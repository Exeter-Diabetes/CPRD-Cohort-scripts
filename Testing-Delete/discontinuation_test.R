
# load libraries
library(tidyverse)

#############################################################################

# load dataset - 1st instance

## this file is the original definition of stopdrug
raw_data_old = "20240308_t2d_1stinstance"

load(paste0("/slade/CPRD_data/mastermind_2022/", raw_data_old, ".Rda"))   # name: t2d_1stinstance

### renaming file to keep concorrent ones
t2d_1stinstance_old <- t2d_1stinstance
rm(t2d_1stinstance)


## this file is the updated NA formulation
raw_data_new = "Pedro_MM/2024-08-08_t2d_1stinstance"

load(paste0("/slade/CPRD_data/mastermind_2022/", raw_data_new, ".Rda"))   # name: t2d_1stinstance

### renaming file to keep concorrent ones
t2d_1stinstance_new <- t2d_1stinstance
rm(t2d_1stinstance)


#############################################################################
##
##  This is the code used by Pedro's T2D discontinuation work
##
#############################################################################

# # Old dataset
# 
# ## numbers
# t2d_1stinstance_old %>%
#   filter(drugclass %in% c("DPP4", "GLP1", "MFN", "SGLT2", "SU", "TZD")) %>%  # drug classes being used
#   filter(!is.na(dm_diag_date)) %>%   # full prescribing data needed
#   mutate(dstartdate = as.Date(dstartdate)) %>%
#   filter(dstartdate > "2014-01-01") %>%   # start date after 2014
#   filter(dstartdate_age >= 18) %>%   # adults
#   select(drugclass, stopdrug_3m_3mFU) %>%
#   table(useNA = "ifany")
# 
# ## percentages
# t2d_1stinstance_old %>%
#   filter(drugclass %in% c("DPP4", "GLP1", "MFN", "SGLT2", "SU", "TZD")) %>%  # drug classes being used
#   filter(!is.na(dm_diag_date)) %>%   # full prescribing data needed
#   mutate(dstartdate = as.Date(dstartdate)) %>%
#   filter(dstartdate > "2014-01-01") %>%   # start date after 2014
#   filter(dstartdate_age >= 18) %>%   # adults
#   select(drugclass, stopdrug_3m_3mFU) %>%
#   table(useNA = "ifany") %>%
#   prop.table(1) %>% `*`(100) %>% round(2) # percentage and rounding
  
############

# New dataset

## numbers
t2d_1stinstance_new %>%
  filter(drugclass %in% c("DPP4", "GLP1", "MFN", "SGLT2", "SU", "TZD")) %>%  # drug classes being used
  filter(!is.na(dm_diag_date)) %>%   # full prescribing data needed
  mutate(dstartdate = as.Date(dstartdate)) %>%
  filter(dstartdate > "2014-01-01") %>%   # start date after 2014
  filter(dstartdate_age >= 18) %>%   # adults
  select(drugclass, stopdrug_3m_3mFU) %>%
  table(useNA = "ifany")

## percentages
t2d_1stinstance_new %>%
  filter(drugclass %in% c("DPP4", "GLP1", "MFN", "SGLT2", "SU", "TZD")) %>%  # drug classes being used
  filter(!is.na(dm_diag_date)) %>%   # full prescribing data needed
  mutate(dstartdate = as.Date(dstartdate)) %>%
  filter(dstartdate > "2014-01-01") %>%   # start date after 2014
  filter(dstartdate_age >= 18) %>%   # adults
  select(drugclass, stopdrug_3m_3mFU) %>%
  table(useNA = "ifany") %>%
  prop.table(1) %>% `*`(100) %>% round(2) # percentage and rounding


plot <- t2d_1stinstance_new %>%
  filter(drugclass %in% c("DPP4", "GLP1", "MFN", "SGLT2", "SU", "TZD")) %>%  # drug classes being used
  filter(!is.na(dm_diag_date)) %>%   # full prescribing data needed
  mutate(dstartdate = as.Date(dstartdate)) %>%
  filter(dstartdate > "2014-01-01") %>%   # start date after 2014
  filter(dstartdate_age >= 18) %>%   # adults
  select(drugclass, stopdrug_3m_3mFU) %>%
  table(useNA = "ifany") %>%
  prop.table(1) %>%
  as.data.frame() %>%
  mutate(stopdrug_3m_3mFU = ifelse(is.na(stopdrug_3m_3mFU), "NA", stopdrug_3m_3mFU)) %>%
  filter(stopdrug_3m_3mFU != "1") %>%
  mutate(stopdrug_3m_3mFU = factor(stopdrug_3m_3mFU, levels = c("2", "3", "4", "5", "NA"), labels = c("1", "2", "3", "4", "NA"))) %>%
  mutate(Outcome = "Outcome: 3-months", `Follow-up` = "Follow-up: 3-months") %>%
  rename("Outcome_var" = "stopdrug_3m_3mFU") %>%
  rbind(
    # Outcome 6m, follow-up 3m
    t2d_1stinstance_new %>%
      filter(drugclass %in% c("DPP4", "GLP1", "MFN", "SGLT2", "SU", "TZD")) %>%  # drug classes being used
      filter(!is.na(dm_diag_date)) %>%   # full prescribing data needed
      mutate(dstartdate = as.Date(dstartdate)) %>%
      filter(dstartdate > "2014-01-01") %>%   # start date after 2014
      filter(dstartdate_age >= 18) %>%   # adults
      select(drugclass, stopdrug_6m_3mFU) %>%
      table(useNA = "ifany") %>%
      prop.table(1) %>%
      as.data.frame() %>%
      mutate(stopdrug_6m_3mFU = ifelse(is.na(stopdrug_6m_3mFU), "NA", stopdrug_6m_3mFU)) %>%
      filter(stopdrug_6m_3mFU != "1") %>%
      mutate(stopdrug_6m_3mFU = factor(stopdrug_6m_3mFU, levels = c("2", "3", "4", "5", "NA"), labels = c("1", "2", "3", "4", "NA"))) %>%
      mutate(Outcome = "Outcome: 6-months", `Follow-up` = "Follow-up: 3-months") %>%
      rename("Outcome_var" = "stopdrug_6m_3mFU"),
    # Outcome 12m, follow-up 3m
    t2d_1stinstance_new %>%
      filter(drugclass %in% c("DPP4", "GLP1", "MFN", "SGLT2", "SU", "TZD")) %>%  # drug classes being used
      filter(!is.na(dm_diag_date)) %>%   # full prescribing data needed
      mutate(dstartdate = as.Date(dstartdate)) %>%
      filter(dstartdate > "2014-01-01") %>%   # start date after 2014
      filter(dstartdate_age >= 18) %>%   # adults
      select(drugclass, stopdrug_12m_3mFU) %>%
      table(useNA = "ifany") %>%
      prop.table(1) %>%
      as.data.frame() %>%
      mutate(stopdrug_12m_3mFU = ifelse(is.na(stopdrug_12m_3mFU), "NA", stopdrug_12m_3mFU)) %>%
      filter(stopdrug_12m_3mFU != "1") %>%
      mutate(stopdrug_12m_3mFU = factor(stopdrug_12m_3mFU, levels = c("2", "3", "4", "5", "NA"), labels = c("1", "2", "3", "4", "NA"))) %>%
      mutate(Outcome = "Outcome: 12-months", `Follow-up` = "Follow-up: 3-months") %>%
      rename("Outcome_var" = "stopdrug_12m_3mFU")
  ) %>%
  mutate(Outcome = factor(Outcome, levels = c("Outcome: 3-months", "Outcome: 6-months", "Outcome: 12-months"))) %>%
  ggplot(aes(x = Freq, y = drugclass, fill = drugclass, alpha = rev(Outcome_var))) +
  geom_bar(stat = "identity", colour = "black") +
  scale_fill_manual(values = c("Pooled" = "black", "SGLT2" = "#E69F00", "GLP1" = "#56B4E9", "SU" = "#CC79A7", "DPP4" = "#0072B2", "TZD" = "#D55E00", "MFN" = "grey"), 
                    breaks = rev(c("MFN", "GLP1", "DPP4", "SGLT2", "TZD", "SU")), labels = rev(c("MFN", "GLP-1RA", "DPP4i", "SGLT2i", "TZD", "SU")),
                    name = "Therapy", guide = guide_legend(reverse = TRUE)) +
  scale_y_discrete(limits = rev, breaks = c("MFN", "GLP1", "DPP4", "SGLT2", "TZD", "SU"), labels = c("Metformin", "GLP-1RA", "DPP4i", "SGLT2i", "TZD", "SU")) +
  scale_alpha_discrete(limits = rev, range = c(1, 0.5), breaks = c("1", "2", "3", "4", "NA"), labels = rev(c("1", "2", "3", "4", "NA")), name = "Discontinuation type:", guide = guide_legend(reverse = TRUE, row = 1)) +
  scale_x_continuous("Proportion of discontinuation", labels = scales::percent) +
  facet_grid(`Follow-up` ~ Outcome) +
  guides(fill = "none") +
  theme_bw() +
  theme(
    legend.position = "bottom",
    legend.box = "vertical",
    plot.title.position = "plot",
    axis.title.y = element_blank(),
    axis.text.x = element_text(size = 14),
    axis.text.y = element_text(size = 14),
    axis.title.x = element_text(size = 15),
    panel.spacing = unit(2, "lines")
  )


pdf("discontinuation_types.pdf", width = 12, height = 5)
plot
dev.off()



