import 'dart:io';
import 'package:conference_darwin/conference_darwin.dart';
import 'package:darwin/darwin.dart';
import 'package:yaml/yaml.dart';

main() async {
  File file = new File('events.yaml');
  String yamlString = file.readAsStringSync();
  Map yaml = loadYaml(yamlString);
  print(yaml);

  var sessions = <Session>[];

  yaml.forEach((key, value) {
    var length = 30;
    if (value["type"] == "keynote") length = 75;
    sessions.add(new Session(key, length, tags: [], avoid: [], seek: []));
  });

  final firstGeneration =
      new Generation<Schedule, int, ScheduleEvaluatorPenalty>()
        ..members.addAll(
            new List.generate(200, (_) => new Schedule.random(sessions)));

  final evaluator = new ScheduleEvaluator(sessions, [dartConfEvaluators]);

  final breeder =
      new GenerationBreeder<Schedule, int, ScheduleEvaluatorPenalty>(
          () => new Schedule(sessions))
        ..fitnessSharingRadius = 0.5
        ..elitismCount = 1;

  final algo = new GeneticAlgorithm<Schedule, int, ScheduleEvaluatorPenalty>(
      firstGeneration, evaluator, breeder,
      printf: (_) {})
    ..maxExperiments = 1000
    ..thresholdResult = new ScheduleEvaluatorPenalty();

  algo.onGenerationEvaluated.listen((gen) {
    if (algo.currentGeneration == 0) return;
    if (algo.currentGeneration % 100 != 0) return;

    printResults(gen, sessions);
  });

  await algo.runUntilDone();
  printResults(algo.generations.last, sessions);
}

void dartConfEvaluators(
    BakedSchedule schedule, ScheduleEvaluatorPenalty penalty) {
  final firstDay = schedule.days[1];
  if (firstDay != null) {
    // Penalize for not ending first day at 6pm.
    final firstDayTargetEnd = new DateTime.utc(
        firstDay.end.year, firstDay.end.month, firstDay.end.day, 18);
    penalty.constraints +=
        firstDay.end.difference(firstDayTargetEnd).inMinutes.abs() / 10;

    // Penalize for too much Flutter in the first block.
    final firstBlock = firstDay.list.takeWhile((s) => !s.session.isBreak);
    if (firstBlock.every((s) => s.session.tags.contains("flutter"))) {
      penalty.repetitiveness += 0.5;
    }
  }
}

void printResults(Generation<Schedule, int, ScheduleEvaluatorPenalty> gen,
    List<Session> sessions) {
  final lastGeneration = new List<Schedule>.from(gen.members);
  lastGeneration.sort();
  for (int i = 0; i < 3; i++) {
    final specimen = lastGeneration[i];
    print("======= Winner $i ("
        "pareto rank ${specimen.result.paretoRank} "
        "fitness ${specimen.result.evaluate().toStringAsFixed(2)} "
        "shared ${specimen.resultWithFitnessSharingApplied.toStringAsFixed(2)} "
        ") ====");
    print("${specimen.genesAsString}");
    print(specimen.generateSchedule(sessions));
  }
}
