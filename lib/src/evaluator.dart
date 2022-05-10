import 'dart:async';
import 'dart:math';
import 'package:conference_darwin/src/baked_schedule.dart';
import 'package:conference_darwin/src/constants.dart';
import 'package:conference_darwin/src/schedule_phenotype.dart';
import 'package:conference_darwin/src/session.dart';
import 'package:darwin/darwin.dart';

class ScheduleEvaluator
    extends PhenotypeEvaluator<Schedule, int, ScheduleEvaluatorPenalty> {
  static const _lunchHourMin = 11;

  static const _lunchHourMax = 13;

  final List<Session> sessions;

  /// Minimal amount of time between breaks.
  final int minBlockLength = 60;

  final int maxMinutesWithoutBreak = 120;

  final int maxMinutesWithoutLargeMeal = 6 * 60;

  final int maxMinutesWithoutDrink = 3 * 60;

  final int maxMinutesInDay = 10 * 60;

  final int targetLunchesPerDay = 1;

  ScheduleEvaluator(this.sessions);

  @override
  Future<ScheduleEvaluatorPenalty> evaluate(Schedule phenotype) {
    return new Future.value(internalEvaluate(phenotype));
  }

  ScheduleEvaluatorPenalty internalEvaluate(Schedule phenotype,
      {bool verbose: false}) {
    final penalty = new ScheduleEvaluatorPenalty();

    final ordered = phenotype.getOrdered(sessions);

    for (final session in sessions) {
      if (!ordered.contains(session)) {
        // A session was left out of the program entirely.
        if (verbose)
          print(session.name + " was left out of the program entirely\n");
        penalty.constraints += 50.0;
      }
    }

    for (int i = 0; i < ordered.length; i++) {
      for (int j = i + 1; j < ordered.length; j++) {
        final first = ordered[i];
        final second = ordered[j];
        if (first.shouldComeAfter(second)) {
          penalty.constraints += 10.0 + (j - i) / 20;
        }
      }
    }

    final days = phenotype.getDays(ordered, sessions).toList(growable: false);
    penalty.constraints += (NUM_DAYS - days.length).abs() * 1000.0;
    if (verbose && days.length != NUM_DAYS)
      print("conference lasts ${days.length} of $NUM_DAYS days\n");

    int dayNumber = 0;
    for (final day in days) {
      dayNumber += 1;
      if (day.isEmpty) {
        if (verbose) print("Day $day is empty\n");
        penalty.cultural += 1000.0;
        continue;
      }
      for (final dayEndSession in day.where((s) => s.isDayEnd)) {
        // end_day sessions should end the day.
        penalty.constraints +=
            (day.length - day.indexOf(dayEndSession) - 1) * 2.0;
        if (verbose && day.indexOf(dayEndSession) < day.length - 1)
          print(
              "Session ${dayEndSession.name} should end a day but does not\n");
      }
      for (final otherDayPreferredSession in day.where(
          (s) => s.preferredDay != null && s.preferredDay != dayNumber)) {
        // Sessions should be scheduled for days they were tagged with (`day2`).
        penalty.constraints += 10.0;
      }
      // Only this many lunches per day. (Normally 1.)
      var targetLunches = targetLunchesPerDay;
      if (dayNumber == days.length && FINAL_HALF_DAY) targetLunches = 0;
      penalty.cultural +=
          (targetLunches - day.where((s) => s.isLunch).length).abs() * 100.0;
      if (verbose && day.where((s) => s.isLunch).length != targetLunches)
        print(
            "Day $dayNumber should have $targetLunches lunches but have ${day.where((s) => s.isLunch).length}\n");
      // Keep the days not too long.
      penalty.awareness +=
          max(0, phenotype.getLength(day) - maxMinutesInDay) / 30;
      if (verbose && phenotype.getLength(day) > maxMinutesInDay)
        print(
            "Day $dayNumber should be $maxMinutesInDay minutes but is ${phenotype.getLength(day)}\n");
    }

    for (final noDrinkBlock
        in phenotype.getBlocksBetweenDrinks(ordered, sessions)) {
      if (noDrinkBlock.isEmpty) continue;

      penalty.hunger +=
          max(0, phenotype.getLength(noDrinkBlock) - maxMinutesWithoutDrink) /
              20;
      if (verbose && phenotype.getLength(noDrinkBlock) > maxMinutesWithoutDrink)
        print(
            "Going without drink for ${phenotype.getLength(noDrinkBlock)} of $maxMinutesWithoutDrink minutes\n");
    }

    for (final noFoodBlock
        in phenotype.getBlocksBetweenLargeMeal(ordered, sessions)) {
      if (noFoodBlock.isEmpty) continue;

      for (final keynoteSession in noFoodBlock.where((s) => s.isKeynote)) {
        // Keynotes should start days or be after lunch.
        penalty.cultural += noFoodBlock.indexOf(keynoteSession) * 50.0;
        if (verbose && noFoodBlock.indexOf(keynoteSession) > 0)
          print(
              "Keynote ${keynoteSession.name} has index ${noFoodBlock.indexOf(keynoteSession)}\n");
      }

      penalty.hunger += max(0,
              phenotype.getLength(noFoodBlock) - maxMinutesWithoutLargeMeal) /
          20;
      if (verbose &&
          phenotype.getLength(noFoodBlock) > maxMinutesWithoutLargeMeal)
        print(
            "Going without food for ${phenotype.getLength(noFoodBlock)} of $maxMinutesWithoutLargeMeal minutes\n");
    }

    void penalizeSeekAvoid(Session a, Session b) {
      const denominator = 2;
      // Avoid according to tags.
      penalty.repetitiveness +=
          a.tags.where((tag) => b.avoid.contains(tag)).length / denominator;
      penalty.repetitiveness +=
          b.tags.where((tag) => a.avoid.contains(tag)).length / denominator;
      // Seek according to tags.
      penalty.harmony -=
          a.tags.where((tag) => b.seek.contains(tag)).length / denominator;
      penalty.harmony -=
          b.tags.where((tag) => a.seek.contains(tag)).length / denominator;

      if (verbose && a.tags.where((tag) => b.avoid.contains(tag)).length > 0)
        print("Sessions ${a.name} and ${b.name} should not be adjacent\n");
      if (verbose && b.tags.where((tag) => a.avoid.contains(tag)).length > 0)
        print("Sessions ${a.name} and ${b.name} should not be adjacent\n");
    }

    for (final block in phenotype.getBlocks(ordered, sessions)) {
      final blockLength = phenotype.getLength(block);
      // Avoid blocks that are too long.
      if (blockLength > maxMinutesWithoutBreak * 1.5) {
        // Block is way too long.
        penalty.awareness += blockLength - maxMinutesWithoutBreak;
      }
      penalty.awareness += max(0, blockLength - maxMinutesWithoutBreak) / 10;
      if (verbose && blockLength > maxMinutesWithoutBreak)
        printf("Block is $blockLength of $maxMinutesWithoutBreak minutes\n");

      // Avoid blocks that are too short.
      penalty.cultural += max(0, minBlockLength - blockLength) / 10;

      if (verbose && blockLength < minBlockLength)
        printf("Block is $blockLength of $minBlockLength minutes\n");

      for (final a in block) {
        for (final b in block) {
          if (a == b) continue;
          penalizeSeekAvoid(a, b);
        }
      }
    }

    for (final tuple in phenotype.getTuples(ordered, sessions)) {
      final a = tuple[0];
      final b = tuple[1];

      penalizeSeekAvoid(a, b);
    }

    final baked = new BakedSchedule(ordered);

    // Penalize when last day is too long.
    final lastDay = baked.days[baked.days.length];
    var diff = lastDay.end.difference(END_TIME).inMinutes.abs();
    if (diff > 0) penalty.constraints += diff;

    // Lunch hour should start at a culturally appropriate time.
    for (final bakedDay in baked.days.values) {
      for (final baked in bakedDay.list) {
        if (!baked.session.isLunch) continue;
        final distance = _getDistanceFromLunchHour(baked.time);
        if (verbose && distance.inMinutes.abs() > 0)
          printf("Lunch is ${distance.inMinutes.abs()} minutes from ideal\n");
        penalty.cultural += distance.inMinutes.abs() / 20;
      }
    }

    // Penalize "hairy" session times (13:05 instead of 13:00).
    for (final day in baked.days.values) {
      for (final session in day.list) {
        if (session.time.minute % 15 != 0) {
          penalty.cultural += 0.01;
        }
      }
    }

    final usedOrderIndexes = new Set<int>();
    for (final order in phenotype.genes) {
      if (usedOrderIndexes.contains(order)) {
        // One index used multiple times.
        penalty.dna += 0.1;
      }
      usedOrderIndexes.add(order);
    }

    return penalty;
  }

  static Duration _getDistanceFromLunchHour(DateTime time) {
    final lunchTimeMin =
        new DateTime.utc(time.year, time.month, time.day, _lunchHourMin);
    final lunchTimeMax =
        new DateTime.utc(time.year, time.month, time.day, _lunchHourMax);
    if (time.isAfter(lunchTimeMin) && time.isBefore(lunchTimeMax) ||
        time == lunchTimeMin ||
        time == lunchTimeMax) {
      // Inside range.
      return const Duration();
    }
    if (time.isBefore(lunchTimeMin)) {
      return lunchTimeMin.difference(time);
    }
    if (time.isAfter(lunchTimeMax)) {
      return lunchTimeMax.difference(time);
    }
    throw new StateError("time has undefined relationship to lunchTimeMin"
        " and lunchTimeMax");
  }
}

class ScheduleEvaluatorPenalty extends FitnessResult {
  /// Penalty for breaking expectations, like lunch at 12pm.
  double cultural = 0.0;

  /// Penalty for breaking constraints, like "end first day at 6pm".
  double constraints = 0.0;

  double hunger = 0.0;

  double repetitiveness = 0.0;

  /// Mostly bonus (negative values) for things like session of the same
  /// theme appearing after each other.
  double harmony = 0.0;

  /// Penalty for straining audience focus, like "not starting with exciting
  /// session after lunch".
  double awareness = 0.0;

  /// Penalty for ambivalence or other problems in the chromosome.
  double dna = 0.0;

  /// Used for debugging only.
  // ignore: unused_field
  double _cachedEvaluate;

  @override
  bool dominates(ScheduleEvaluatorPenalty other) {
    return cultural < other.cultural &&
        constraints < other.constraints &&
        hunger < other.hunger &&
        repetitiveness < other.repetitiveness &&
        harmony < other.harmony &&
        awareness < other.awareness &&
        dna < other.dna;
  }

  double evaluate() {
    double result = 0.0;
    result += cultural;
    result += constraints;
    result += hunger;
    result += repetitiveness;
    result += harmony;
    result += awareness;
    result += dna;
    _cachedEvaluate = result;
    return result;
  }
}

/// A function that takes a [schedule] and modifies the [penalty].
///
/// These are used for specific rules pertaining to only one conference but
/// not generally applicable, such as that a particular conference's first day
/// must end as close to 6pm as possible.
typedef void CustomEvaluator(
    BakedSchedule schedule, ScheduleEvaluatorPenalty penalty);
