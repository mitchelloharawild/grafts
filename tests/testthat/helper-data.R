# Two quarterly years of a small State / Region x Purpose structure
small <- local({
  regions <- data.frame(State = c("A", "A", "B"), Region = c("a1", "a2", "b1"))
  grid <- merge(
    merge(data.frame(Quarter = tsibble::yearquarter("2020 Q1") + 0:7), regions),
    data.frame(Purpose = c("Work", "Play"))
  )
  grid$y <- seq_len(nrow(grid))
  tsibble::as_tsibble(grid, index = Quarter, key = c(State, Region, Purpose))
})

model_of <- function(data, ...) {
  explore_model(data, rlang::quo(NULL), NULL, c(80, 95), 1000, ...)
}
