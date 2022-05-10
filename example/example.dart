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
    var tags = <String>[];
    var name = key;
    var avoid = <String>[];

    // Get the name of the event
    if (value["type"] == "keynote") name += " - " + value["speaker"];

    // Get the duration of the event
    if (value["type"] == "keynote")
      length = 75;
    else if (value["type"] == "lunch") length = 90;
    if (value["duration"] != null) length = value["duration"];

    // Set tags
    if (value["type"] == "keynote") tags = ["keynote"];
    if (value["type"] == "lunch") tags = ["lunch", "break"];
    if (value["type"] == "poster") tags = ["day_end"];

    // Set avoid
    if (value["type"] == "lunch") avoid = ["break"];

    sessions.add(new Session(name, length, tags: tags, avoid: avoid));
  });

  final firstGeneration =
      new Generation<Schedule, int, ScheduleEvaluatorPenalty>()
        ..members.addAll(
            new List.generate(200, (_) => new Schedule.random(sessions, 11)));

  final evaluator = new ScheduleEvaluator(sessions, [dartConfEvaluators]);

  final breeder =
      new GenerationBreeder<Schedule, int, ScheduleEvaluatorPenalty>(
          () => new Schedule(sessions, 11))
        ..fitnessSharingRadius = 0.5
        ..elitismCount = 1;

  final algo = new GeneticAlgorithm<Schedule, int, ScheduleEvaluatorPenalty>(
      firstGeneration, evaluator, breeder,
      printf: (_) {})
    ..maxExperiments = 100000
    ..thresholdResult = new ScheduleEvaluatorPenalty();

  algo.onGenerationEvaluated.listen((gen) {
    if (algo.currentGeneration == 0) return;
    if (algo.currentGeneration % 100 != 0) return;

    printResults(gen, sessions, evaluator);
  });

  await algo.runUntilDone();
  printResults(algo.generations.last, sessions, evaluator);
}

void dartConfEvaluators(
    BakedSchedule schedule, ScheduleEvaluatorPenalty penalty) {
  final lastDay = schedule.days[5];
  if (lastDay != null) {
    // Penalize for not ending last day at 1:30pm.
    final firstDayTargetEnd = new DateTime.utc(
        lastDay.end.year, lastDay.end.month, lastDay.end.day, 13, 30);
    penalty.constraints +=
        lastDay.end.difference(firstDayTargetEnd).inMinutes.abs() / 10;
  }
}

void printResults(Generation<Schedule, int, ScheduleEvaluatorPenalty> gen,
    List<Session> sessions, ScheduleEvaluator evaluator) {
  final lastGeneration = new List<Schedule>.from(gen.members);
  lastGeneration.sort();
  for (int i = 0; i < 1; i++) {
    final specimen = lastGeneration[i];
    evaluator.internalEvaluate(specimen, verbose: true);
    print("======= Winner $i ("
        "pareto rank ${specimen.result.paretoRank} "
        "fitness ${specimen.result.evaluate().toStringAsFixed(2)} "
        "shared ${specimen.resultWithFitnessSharingApplied.toStringAsFixed(2)} "
        ") ====");
    print("${specimen.genesAsString}");
    print(specimen.generateSchedule(sessions));
  }
}
