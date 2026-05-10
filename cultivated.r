# =============================================================================
# Cultivated Meat Startups — Text & Funding Analysis
# =============================================================================



# =========================
# 0) Housekeeping
# =========================

rm(list = ls())
graphics.off()

# Рабочая директория — подставь свой путь
setwd("C:/Users/DmitryK/Desktop/Master thesis/thesis_r")

# Папка для всех выходных файлов
out_dir <- file.path(getwd(), "outputs")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# Быстрая проверка прав записи
writeLines("ok", file.path(out_dir, "write_test.txt"))
message("Output dir OK: ", normalizePath(out_dir))



# =========================
# 1) Packages
# =========================

required <- c("dplyr", "readr", "stringr", "tidyr", "tidytext",
              "purrr", "readxl", "quanteda", "quanteda.dictionaries",
              "textdata", "ggplot2", "broom")

# Устанавливаем только то, чего ещё нет
to_install <- setdiff(required, rownames(installed.packages()))
if (length(to_install) > 0) install.packages(to_install)

# quanteda.dictionaries — только с GitHub
if (!requireNamespace("quanteda.dictionaries", quietly = TRUE)) {
  if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
  remotes::install_github("kbenoit/quanteda.dictionaries")
}

invisible(lapply(required, library, character.only = TRUE))



# =========================
# 2) Read Excel
# =========================

startup <- readxl::read_excel(
  "startup_table.xlsx",     # файл должен лежать в рабочей директории
  sheet     = "startup_table",
  guess_max = 10000
)

stopifnot(is.data.frame(startup))
stopifnot(all(c("company", "mission", "value", "about",
                "round_amount1", "round_amount2", "total_funding") %in% names(startup)))

print(dplyr::glimpse(startup))



# =========================
# 3) Clean text + build one analysis field
# =========================

startup <- startup %>%
  mutate(
    company = stringr::str_squish(as.character(company)),
    mission = dplyr::coalesce(as.character(mission), ""),
    value   = dplyr::coalesce(as.character(value),   ""),
    about   = dplyr::coalesce(as.character(about),   ""),
    text = stringr::str_squish(paste(mission, value, about, sep = "\n\n")),
    word_count = stringr::str_count(text, "\\S+"),
    text_date  = Sys.Date()
  ) %>%
  filter(company != "")

# Сохраняем clean table (для проверки)
readr::write_csv(startup, file.path(out_dir, "startup_clean.csv"))

# Отчёт по длине текстов
message("\n--- Word count по компаниям ---")
startup %>%
  select(company, word_count) %>%
  mutate(flag = case_when(
    word_count == 0   ~ "ПУСТО — нет текста",
    word_count < 80   ~ "< 80 слов — выпадет из анализа",
    word_count < 100  ~ "80–99 слов — граничный случай",
    TRUE              ~ "OK"
  )) %>%
  print(n = Inf)



# =========================
# 4) Funding parsing
#    Обрабатывает: числа, "5.2", "5,2", "=SUM(H10,J10)" (Excel-формулы),
#    "=22.6+18" (формула с арифметикой), K/M/B суффиксы, "1.5+0.5" суммы
# =========================

parse_musd_scalar <- function(x) {
  if (is.na(x)) return(NA_real_)

  # если уже число — просто вернуть
  if (is.numeric(x)) return(as.numeric(x))

  x <- stringr::str_squish(as.character(x))
  if (x == "") return(NA_real_)

  # Excel-формула "=SUM(H10,J10)" — нельзя вычислить, вернём NA
  # (readxl читает формулы как строки, не вычисляет их)
  if (grepl("^=SUM\\(", x, ignore.case = TRUE)) {
    # Попробуем вытащить числа из аргументов: =SUM(47, 176) → 223
    # Но если аргументы — адреса ячеек (H10, J10), вернём NA
    inner <- stringr::str_match(x, "^=SUM\\((.+)\\)$")[,2]
    if (!is.na(inner)) {
      nums <- suppressWarnings(as.numeric(unlist(strsplit(inner, ","))))
      if (!all(is.na(nums))) return(sum(nums, na.rm = TRUE))
    }
    return(NA_real_)
  }

  # Excel-формула с арифметикой: "=22.6+18" → вычислим
  if (grepl("^=", x)) {
    expr_str <- gsub("^=", "", x)
    expr_str <- gsub(",", ".", expr_str)   # на случай европейской запятой
    result   <- tryCatch(eval(parse(text = expr_str)), error = function(e) NA_real_)
    if (is.numeric(result)) return(result)
    return(NA_real_)
  }

  # Обычные строки: "1,5+0,5", "$5.2M", "400K" и т.д.
  parts <- unlist(strsplit(x, "\\+"))

  part_to_musd <- function(p) {
    p   <- gsub("\\s+|\\$|€", "", p)
    p   <- gsub(",", ".", p)                      # запятая → точка
    suf <- stringr::str_extract(p, "[KMBkmb]$")
    num <- suppressWarnings(as.numeric(stringr::str_remove(p, "[KMBkmb]$")))
    if (is.na(num)) return(NA_real_)
    if (!is.na(suf)) {
      suf <- toupper(suf)
      if (suf == "K") return(num / 1000)          # тысячи → миллионы
      if (suf == "M") return(num)
      if (suf == "B") return(num * 1000)
    }
    num   # без суффикса — считаем миллионы
  }

  vals <- vapply(parts, part_to_musd, numeric(1))
  if (all(is.na(vals))) NA_real_ else sum(vals, na.rm = TRUE)
}

parse_musd <- function(vec) vapply(vec, parse_musd_scalar, numeric(1))

startup <- startup %>%
  mutate(
    round1_musd        = parse_musd(round_amount1),
    round2_musd        = parse_musd(round_amount2),
    total_funding_musd = parse_musd(total_funding)
  ) %>%
  mutate(
    # Если total пустой или нечитаемый (Excel-формула с адресами) —
    # считаем сами из round1 + round2
    total_funding_musd = ifelse(
      is.na(total_funding_musd),
      rowSums(cbind(round1_musd, round2_musd), na.rm = TRUE),
      total_funding_musd
    ),
    # rowSums возвращает 0 если оба NA — заменяем обратно на NA
    total_funding_musd = ifelse(
      total_funding_musd == 0 & is.na(round1_musd) & is.na(round2_musd),
      NA_real_,
      total_funding_musd
    ),
    total_funding_usd = total_funding_musd * 1e6,
    log_funding       = log1p(dplyr::coalesce(total_funding_musd, 0)),
    funded_dummy      = as.integer(!is.na(total_funding_musd) & total_funding_musd > 0)
  )

# Контроль: убедись, что суммы считались правильно
message("\n--- Контроль funding ---")
startup %>%
  select(company, round_amount1, round1_musd,
         round_amount2, round2_musd,
         total_funding, total_funding_musd, log_funding) %>%
  print(n = Inf)



# =========================
# 5) QC-фильтр по длине текста
# =========================

min_words <- 80   # порог: компании с текстом короче этого выпадают из анализа
                  # можно поставить 100 для более строгого фильтра

startup_qc <- startup %>% filter(word_count >= min_words)

message(sprintf(
  "\nQC-фильтр (>= %d слов): осталось %d из %d компаний",
  min_words, nrow(startup_qc), nrow(startup)
))

# Компании, которые выпали
startup %>%
  filter(word_count < min_words) %>%
  select(company, word_count) %>%
  { if (nrow(.) > 0) { message("Выпали из анализа:"); print(.) } }



# =========================
# 6) Moral Foundations (MFD 2.0) — per 1k words
# =========================

corp    <- quanteda::corpus(startup_qc, text_field = "text", docid_field = "company")
toks    <- quanteda::tokens(corp, remove_punct = TRUE, remove_numbers = TRUE) %>%
             quanteda::tokens_tolower()
dfm_mat <- quanteda::dfm(toks)

mfd_counts <- quanteda::dfm_lookup(dfm_mat,
                dictionary = quanteda.dictionaries::data_dictionary_MFD)

mfd_raw <- quanteda::convert(mfd_counts, to = "data.frame") %>%
  rename(company = doc_id) %>%
  left_join(startup_qc %>% select(company, word_count), by = "company")

mfd_cols <- setdiff(names(mfd_raw), c("company", "word_count"))

mfd_df <- mfd_raw %>%
  mutate(across(all_of(mfd_cols),
                ~ (.x / pmax(word_count, 1)) * 1000,
                .names = "{.col}_per1k")) %>%
  select(company, ends_with("_per1k")) %>%
  rowwise() %>%
  mutate(moral_total_per1k = sum(c_across(ends_with("_per1k")), na.rm = TRUE)) %>%
  ungroup()



# =========================
# 7) Sentiment + emotions (NRC) — per 1k words
#    Fallback на Bing, если NRC не загрузился
# =========================

tidy_words <- startup_qc %>%
  select(company, text, word_count) %>%
  tidytext::unnest_tokens(word, text)

nrc <- tryCatch(
  tidytext::get_sentiments("nrc"),
  error = function(e) {
    message("NRC не загрузился, используется Bing как fallback: ", conditionMessage(e))
    NULL
  }
)

if (!is.null(nrc)) {
  nrc_scores <- tidy_words %>%
    inner_join(nrc, by = "word") %>%
    count(company, sentiment, name = "n") %>%
    left_join(startup_qc %>% select(company, word_count), by = "company") %>%
    mutate(per1k = (n / pmax(word_count, 1)) * 1000) %>%
    select(company, sentiment, per1k) %>%
    pivot_wider(names_from = sentiment, values_from = per1k, values_fill = 0)
} else {
  bing <- tidytext::get_sentiments("bing")
  nrc_scores <- tidy_words %>%
    inner_join(bing, by = "word") %>%
    count(company, sentiment, name = "n") %>%
    left_join(startup_qc %>% select(company, word_count), by = "company") %>%
    mutate(per1k = (n / pmax(word_count, 1)) * 1000) %>%
    select(company, sentiment, per1k) %>%
    pivot_wider(names_from = sentiment, values_from = per1k, values_fill = 0)
}

print(nrc_scores)



# =========================
# 8) Temporality (future vs past) — per 1k words
# =========================

future_terms <- c(
  "will", "future", "tomorrow", "next", "soon", "upcoming", "forthcoming",
  "long-term", "longterm", "short-term", "shortterm",
  "vision", "aim", "goal", "mission", "purpose", "ambition", "aspiration",
  "strategy", "roadmap", "trajectory", "direction", "outlook",
  "scale", "expand", "growth", "accelerate", "advance", "progress",
  "develop", "evolve", "build", "drive", "enable", "unlock",
  "transform", "transformation", "revolution", "revolutionize",
  "reimagine", "reinvent", "reshape", "disrupt", "innovation",
  "innovative", "breakthrough",
  "plan", "planned", "planning", "intend", "intention", "target",
  "commit", "commitment", "pursue", "focus", "seek",
  "can", "could", "may", "might", "should",
  "opportunity", "potential", "prospect", "promise",
  "pipeline", "launch", "commercialize", "commercialization"
)

past_terms <- c(
  "since", "founded", "launched", "began", "started", "established",
  "created", "built", "developed", "introduced",
  "achieved", "milestone", "milestones", "accomplished", "delivered",
  "completed", "secured", "obtained", "reached", "attained",
  "history", "historical", "track record", "experience", "background",
  "heritage", "legacy", "foundation",
  "years", "year", "previously", "earlier", "formerly", "initially",
  "already", "currently", "to date",
  "grew", "expanded", "scaled", "advanced", "progressed",
  "demonstrated", "validated", "proven", "tested", "confirmed",
  "raised", "funded", "backed", "supported", "partnered",
  "approved", "certified", "authorized", "granted", "filed",
  "was", "were", "had", "did", "led", "made"
)

present_terms <- c("today", "now", "currently")

temp_dict <- quanteda::dictionary(list(
  FUTURE  = future_terms,
  PAST    = past_terms,
  PRESENT = present_terms        # добавили третью категорию
))

temp_counts <- quanteda::dfm_lookup(dfm_mat, dictionary = temp_dict)

temp_df <- quanteda::convert(temp_counts, to = "data.frame") %>%
  rename(company = doc_id) %>%
  left_join(startup_qc %>% select(company, word_count), by = "company") %>%
  mutate(
    future_per1k  = (FUTURE  / pmax(word_count, 1)) * 1000,
    past_per1k    = (PAST    / pmax(word_count, 1)) * 1000,
    present_per1k = (PRESENT / pmax(word_count, 1)) * 1000
  ) %>%
  select(company, future_per1k, past_per1k, present_per1k)



# =========================
# 9) Merge + финальная таблица признаков
# =========================

features <- startup_qc %>%
  left_join(mfd_df,     by = "company") %>%
  left_join(nrc_scores, by = "company") %>%
  left_join(temp_df,    by = "company") %>%
  mutate(
    # 2b: ratio — доля будущего в общем темпоральном языке
    future_ratio = future_per1k / (future_per1k + past_per1k + 0.001)
  )


# Быстрая финальная проверка
features %>%
  select(company, word_count, total_funding_musd,
         moral_total_per1k, positive, negative, trust, fear,
         future_per1k, past_per1k) %>%
  print(n = Inf)

readr::write_csv(features, file.path(out_dir, "startup_text_features.csv"))



# =========================
# 10) Descriptive statistics (Table 1)
# =========================

desc_vars <- c("word_count", "total_funding_musd",
               "moral_total_per1k", "positive", "negative",
               "trust", "fear", "future_per1k", "past_per1k")

descriptives <- features %>%
  filter(!is.na(total_funding_musd)) %>%
  summarise(
    n = n(),
    mean_words          = mean(word_count,          na.rm = TRUE),
    median_words        = median(word_count,        na.rm = TRUE),
    mean_funding_musd   = mean(total_funding_musd,  na.rm = TRUE),
    median_funding_musd = median(total_funding_musd,na.rm = TRUE),
    mean_moral          = mean(moral_total_per1k,   na.rm = TRUE),
    mean_positive       = mean(positive,            na.rm = TRUE),
    mean_negative       = mean(negative,            na.rm = TRUE),
    mean_trust          = mean(trust,               na.rm = TRUE),
    mean_fear           = mean(fear,                na.rm = TRUE),
    mean_future         = mean(future_per1k,        na.rm = TRUE),
    mean_past           = mean(past_per1k,          na.rm = TRUE)
  )

print(descriptives)
readr::write_csv(descriptives, file.path(out_dir, "descriptives.csv"))



# =========================
# 11) Correlation matrix (Table 2)
# =========================

cor_vars <- c("log_funding", "total_funding_musd",
              "moral_total_per1k", "positive", "negative",
              "trust", "fear", "future_per1k", "past_per1k", "word_count")

cor_data <- features %>%
  filter(!is.na(total_funding_musd)) %>%
  select(any_of(cor_vars))

cor_matrix <- round(cor(cor_data, use = "pairwise.complete.obs"), 3)
print(cor_matrix)

readr::write_csv(
  as.data.frame(cor_matrix),
  file.path(out_dir, "correlation_matrix.csv")
)



# =========================
# 12) Regression models (Table 3)
# =========================

reg_data <- features %>%
  filter(!is.na(total_funding_musd), word_count >= min_words)

# Model 1: moral framing → funding
m1        <- lm(log_funding ~ moral_total_per1k, data = reg_data)
reg_moral <- broom::tidy(m1)
print(reg_moral)

# Model 2: future orientation → funding
m2         <- lm(log_funding ~ future_per1k, data = reg_data)
reg_future <- broom::tidy(m2)
print(reg_future)

# Model 3: trust + positive affect → funding
m3              <- lm(log_funding ~ trust + positive, data = reg_data)
reg_trust_pos   <- broom::tidy(m3)
print(reg_trust_pos)

# Model 4: полная модель с контролями
m4 <- lm(log_funding ~ moral_total_per1k + trust + positive +
           future_per1k + word_count + founded_year,
         data = reg_data)
summary(m4)

readr::write_csv(reg_moral,    file.path(out_dir, "reg_moral.csv"))
readr::write_csv(reg_future,   file.path(out_dir, "reg_future.csv"))
readr::write_csv(reg_trust_pos,file.path(out_dir, "reg_trust_positive.csv"))


# Model 5: квадратичная — нелинейный эффект future orientation (2c)
m5        <- lm(log_funding ~ future_per1k + I(future_per1k^2), data = reg_data)
reg_quad  <- broom::tidy(m5)
print(summary(m5))

# Model 6: полная модель с контролями региона и бизнес-модели (2d)
# Сначала делаем dummy-переменные
reg_data <- reg_data %>%
  mutate(
    region_grouped = case_when(
      region %in% c("US", "Israel / US")          ~ "North_America_Israel",
      region %in% c("Netherlands", "Germany",
                    "UK", "France", "Switzerland") ~ "Europe",
      region %in% c("China", "Shanghai",
                    "South Korea", "Singapore",
                    "Hong Kong", "Australia")      ~ "Asia_Pacific",
      TRUE                                          ~ "Other"
    ),
    b2b_dummy = ifelse(B2B_B2C == "B2B", 1, 0)
  )

m6 <- lm(log_funding ~ moral_total_per1k + future_per1k + future_ratio +
            trust + positive + word_count +
            founded_year + region_grouped + b2b_dummy,
          data = reg_data)
summary(m6)

readr::write_csv(reg_quad, file.path(out_dir, "reg_quadratic.csv"))
readr::write_csv(broom::tidy(m6), file.path(out_dir, "reg_full_controls.csv"))


# =========================
# 13) Figure 1 — future orientation vs funding
# =========================

plot_data <- reg_data %>%
  filter(!is.na(future_per1k), !is.na(log_funding))

p <- ggplot(plot_data, aes(x = future_per1k, y = log_funding)) +
  geom_point(size = 2.5, alpha = 0.7) +
  geom_smooth(method = "lm", se = TRUE, color = "steelblue") +
  labs(
    title = "Future orientation and funding",
    x     = "Future-oriented words (per 1,000)",
    y     = "Log(1 + total funding)"
  ) +
  theme_minimal(base_size = 12)

ggsave(file.path(out_dir, "plot_future_vs_funding.png"),
       plot = p, width = 7, height = 5, dpi = 150)







# =========================
# Итоговый список файлов в outputs/
# =========================

message("\nСохранено в: ", normalizePath(out_dir))
list.files(out_dir)