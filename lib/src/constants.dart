final int COFFEE_LENGTH = 30;
final int LUNCH_LENGTH = 90;
final int SHORT_LENGTH = 5;

final Map DURATIONS = {
  "minisymposium": 100,
  "keynote": 75,
  "lunch": LUNCH_LENGTH,
  "poster": 120,
  "default": 30
};

final Map TAGS = {
  "minisymposium": ["minisymposium"],
  "keynote": ["keynote"],
  "lunch": ["lunch", "break", "not_final_day"],
  "poster": ["day_end", "not_final_day", "subsequent_days", "coffee"],
  "default": <String>[]
};

final Map SEEK = {
  "minisymposium": ["break"],
  "keynote": ["break"],
  "lunch": <String>[],
  "poster": <String>[],
  "default": <String>[]
};

final Map AVOID = {
  "minisymposium": <String>[],
  "keynote": <String>[],
  "lunch": ["break"],
  "poster": ["coffee", "short"],
  "default": <String>[]
};
