enum TimePrecision { centisecond, decisecond }

extension TimePrecisionPrefs on TimePrecision {
  String get storageValue =>
      this == TimePrecision.centisecond ? 'centisecond' : 'decisecond';
}

TimePrecision precisionFromStorage(String? raw) {
  if (raw == TimePrecision.decisecond.storageValue) {
    return TimePrecision.decisecond;
  }
  return TimePrecision.centisecond;
}
