/// Starter outline for the 90-day programme. It is only a starting point:
/// edit, add or delete any lesson under Settings > Curriculum.
/// Topics follow the vocabulary of your study (market profile, TPO, POC,
/// value area, initiative/responsive, acceptance/rejection, balance/trend).
class SeedLesson {
  const SeedLesson(this.title, this.objective);
  final String title;
  final String objective;
}

class SeedWeek {
  const SeedWeek(this.phaseNo, this.phaseTitle, this.theme, this.lessons,
      {this.endsPhase = false});
  final int phaseNo;
  final String phaseTitle;
  final String theme;

  /// Monday to Friday.
  final List<SeedLesson> lessons;
  final bool endsPhase;
}

const List<SeedWeek> curriculumSeed = [
  // ---------------- Phase 1: Foundations ----------------
  SeedWeek(1, 'Foundations', 'Auction basics', [
    SeedLesson('Markets as two-way auctions', 'Explain price discovery in your own words.'),
    SeedLesson('Time, price and volume', 'Describe how each dimension is used in the profile approach.'),
    SeedLesson('Orientation to Mind Over Markets', 'Skim the book and list the chapters you will read in the coming weeks.'),
    SeedLesson('Balance and imbalance', 'Define balance and imbalance, and find one chart example of each.'),
    SeedLesson('Instruments and timeframes', 'Decide which instruments and timeframes you will study (for example XAUUSD, BTCUSD, US100 on 15M, 30M, 1H) and why.'),
  ]),
  SeedWeek(1, 'Foundations', 'Profile construction', [
    SeedLesson('TPO letters and the profile', 'Build one session profile by hand.'),
    SeedLesson('Point of control (POC)', 'Locate and describe the POC on three profiles.'),
    SeedLesson('Value area', 'Work out a value area step by step and note the rule you used.'),
    SeedLesson('Profile shapes', 'Identify the shapes in five sessions.'),
    SeedLesson('Session structure', 'Describe the opening period and how the range develops.'),
  ], endsPhase: true),
  // ---------------- Phase 2: Reading the profile ----------------
  SeedWeek(2, 'Reading the profile', 'Day structure', [
    SeedLesson('Day types: overview', 'List the day types defined in your book.'),
    SeedLesson('Normal and normal-variation days', 'Recognise each in two examples.'),
    SeedLesson('Trend days', 'Note what a trend day looked like in two examples.'),
    SeedLesson('Double distribution and neutral days', 'Recognise each in two examples.'),
    SeedLesson('Classify five past sessions', 'Label five sessions and write why.'),
  ]),
  SeedWeek(2, 'Reading the profile', 'Value relationships', [
    SeedLesson('Value relative to the prior day', 'Describe how today\'s value sits against yesterday\'s.'),
    SeedLesson('Opening location', 'Record where the session opens relative to prior value.'),
    SeedLesson('Acceptance back into value', 'Find examples of price returning to prior value.'),
    SeedLesson('Multi-day context', 'Write a short context note across three days.'),
    SeedLesson('Practice: context notes', 'Write context notes for five sessions.'),
  ]),
  SeedWeek(2, 'Reading the profile', 'Reference levels', [
    SeedLesson('Prior high, low, close and POC', 'Use prior-session levels as references on a chart.'),
    SeedLesson('Poor highs and lows, excess', 'Identify an example of each.'),
    SeedLesson('Composite and multi-day profiles', 'Build one composite view.'),
    SeedLesson('Choosing a reference level for a case', 'Practise recording the reference level in a Research case.'),
    SeedLesson('Practice: phase review', 'Review the notes from this phase and list open questions.'),
  ], endsPhase: true),
  // ---------------- Phase 3: Activity and acceptance ----------------
  SeedWeek(3, 'Activity and acceptance', 'Initiative and responsive activity', [
    SeedLesson('Definitions', 'Write the definitions of initiative and responsive activity in your own words.'),
    SeedLesson('Identifying initiative activity', 'Mark examples on three charts.'),
    SeedLesson('Identifying responsive activity', 'Mark examples on three charts.'),
    SeedLesson('Other-timeframe participants', 'Summarise the idea in a short note.'),
    SeedLesson('Practice on three charts', 'Annotate three charts and compare with your notes.'),
  ]),
  SeedWeek(3, 'Activity and acceptance', 'Acceptance and rejection', [
    SeedLesson('What acceptance looks like', 'Describe it using time spent and price travelled.'),
    SeedLesson('What rejection looks like', 'Describe it using three examples.'),
    SeedLesson('Time versus price', 'Compare time spent at a level with distance travelled.'),
    SeedLesson('Failed exploration', 'Find and describe three examples.'),
    SeedLesson('Practice: acceptance and rejection', 'Mark acceptance and rejection on five charts.'),
  ]),
  SeedWeek(3, 'Activity and acceptance', 'Exploration and excess', [
    SeedLesson('Directional exploration beyond value', 'Record the direction and what followed in two examples.'),
    SeedLesson('Return to value after failed exploration', 'Find two examples.'),
    SeedLesson('Excess and tails', 'Identify examples and what they might signal.'),
    SeedLesson('Alternative scenarios', 'Practise writing more than one possible scenario for a chart.'),
    SeedLesson('Practice: phase review', 'Review notes, list what is still unclear.'),
  ], endsPhase: true),
  // ---------------- Phase 4: Transitions and research ----------------
  SeedWeek(4, 'Transitions and research', 'Balance to trend and back', [
    SeedLesson('What changes at a transition', 'List the observations that change.'),
    SeedLesson('Signs of a developing trend', 'Record observations from two examples.'),
    SeedLesson('Signs of balance resuming', 'Record observations from two examples.'),
    SeedLesson('Ambiguous transitions', 'Practise recording the alternatives instead of forcing one answer.'),
    SeedLesson('Practice cases', 'Create three Research cases about transitions.'),
  ]),
  SeedWeek(4, 'Transitions and research', 'Writing hypotheses', [
    SeedLesson('A hypothesis before the outcome', 'Write one and lock it before looking ahead.'),
    SeedLesson('Evidence for and against', 'List both sides for a case.'),
    SeedLesson('Invalidation conditions', 'State what would prove the hypothesis wrong.'),
    SeedLesson('Confidence levels', 'Record a confidence level and compare it with outcomes later.'),
    SeedLesson('Write and lock three hypotheses', 'Create three cases and lock their hypotheses.'),
  ]),
  SeedWeek(4, 'Transitions and research', 'Research method', [
    SeedLesson('Building the dataset', 'Record instrument, timeframe and condition consistently.'),
    SeedLesson('Recording outcomes honestly', 'Record outcomes without rewriting the original hypothesis.'),
    SeedLesson('Avoiding hindsight', 'Reflect on how hindsight changes interpretation.'),
    SeedLesson('Reviewing a batch of cases', 'Review at least five closed cases.'),
    SeedLesson('Practice: phase review', 'Summarise what your cases show and what they do not prove.'),
  ], endsPhase: true),
  // ---------------- Phase 5: Review and process ----------------
  SeedWeek(5, 'Review and process', 'Risk and records', [
    SeedLesson('Research versus execution', 'Explain the difference and why records are kept apart.'),
    SeedLesson('Demo and live records', 'Review how demo and live trades are kept separate.'),
    SeedLesson('Risk per trade (records only)', 'Record the planned risk for each demo trade.'),
    SeedLesson('Rule adherence and process notes', 'Record whether your rules were followed and why.'),
    SeedLesson('Costs in the records', 'Record spread and commission with each trade.'),
  ]),
  SeedWeek(5, 'Review and process', 'Consolidation', [
    SeedLesson('Review every case', 'Count hypotheses supported, contradicted and inconclusive.'),
    SeedLesson('Recurring mistakes', 'List patterns in your mistakes.'),
    SeedLesson('Unanswered questions', 'Collect your open questions.'),
    SeedLesson('Plan the next course', 'Decide what you will study next.'),
    SeedLesson('Final reflection', 'Write what changed in how you read markets.'),
  ], endsPhase: true),
];
