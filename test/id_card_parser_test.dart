import 'package:flutter_test/flutter_test.dart';
import 'package:thanima_app/services/id_card_parser.dart';

// What ML Kit actually returns for the reference card, boilerplate and all.
const referenceCard = '''
VIT
Vellore Institute of Technology
(Deemed to be University under section 3 of the UGC Act, 1956)
CHENNAI CAMPUS
Arjun Menon
23BCE1042
HOSTELLER
''';

void main() {
  test('reads name and reg no off the reference card', () {
    final scan = IdCardParser.parse(referenceCard);
    expect(scan.regNo, '23BCE1042');
    expect(scan.name, 'Arjun Menon');
    expect(scan.isComplete, isTrue);
  });

  test('never mistakes the institution for the name', () {
    // The longest all-letters line is "Vellore Institute of Technology" — a
    // naive heuristic returns that. Anchoring on the reg no does not.
    final scan = IdCardParser.parse(referenceCard);
    expect(scan.name, isNot(contains('Institute')));
    expect(scan.name, isNot(contains('CAMPUS')));
  });

  test('tolerates spacing the OCR invents in the reg no', () {
    final scan = IdCardParser.parse('Ravi Kumar M\n23 BCE 1042\nHOSTELLER');
    expect(scan.regNo, '23BCE1042');
    expect(scan.name, 'Ravi Kumar M');
  });

  test('repairs characters the OCR confuses, positionally', () {
    // B->8, I->1 and O->0, but only where the format demands a digit.
    expect(IdCardParser.parse('Asha R\n23BCE104B').regNo, '23BCE1048');
    expect(IdCardParser.parse('Asha R\n2IBCE1042').regNo, '21BCE1042');
    expect(IdCardParser.parse('Asha R\n23BCE1O42').regNo, '23BCE1042');
    // The B in the BCE branch code is a letter and must be left alone.
    expect(IdCardParser.parse('Asha R\n23BCE1042').regNo, '23BCE1042');
  });

  test('handles a four-letter branch code', () {
    final scan = IdCardParser.parse('Meera S\n23MECH1042\nDAYSCHOLAR');
    expect(scan.regNo, '23MECH1042');
    expect(scan.name, 'Meera S');
  });

  test('returns nulls rather than guesses when the card is unreadable', () {
    final scan = IdCardParser.parse('VIT\nCHENNAI CAMPUS\nHOSTELLER');
    expect(scan.regNo, isNull);
    expect(scan.name, isNull);
    expect(scan.isComplete, isFalse);
  });

  test('finds the name below the number when the layout is flipped', () {
    final scan = IdCardParser.parse('VIT\n23BCE1042\nArjun Menon');
    expect(scan.regNo, '23BCE1042');
    expect(scan.name, 'Arjun Menon');
  });

  // Boilerplate is matched as whole words. Substring matching would throw
  // away real names: VIT is inside Kavita/Savita/Vitthal, CARD inside Cardoza.
  test('keeps names that merely contain a boilerplate word', () {
    for (final name in ['Kavita Menon', 'Savita R', 'Vitthal Rao', 'Cardoza Fernandes']) {
      final scan = IdCardParser.parse('CHENNAI CAMPUS\n$name\n23BCE1042');
      expect(scan.name, name, reason: '"$name" must survive the blocklist');
    }
  });

  test('accepts apostrophes and hyphens in names', () {
    expect(IdCardParser.parse("D'Souza Maria\n23BCE1042").name, "D'Souza Maria");
    expect(IdCardParser.parse('Anne-Marie K\n23BCE1042').name, 'Anne-Marie K');
  });

  test('still rejects the institution lines', () {
    final scan = IdCardParser.parse(
      'Vellore Institute of Technology\nCHENNAI CAMPUS\n23BCE1042\nHOSTELLER',
    );
    expect(scan.regNo, '23BCE1042');
    expect(scan.name, isNull);
  });

  test('skips a stray initial and takes the real name line', () {
    final scan = IdCardParser.parse('Meera Krishnan\nP\n23BCE1042');
    expect(scan.name, 'Meera Krishnan');
  });

  test('does not accept a phone number or a date as a reg no', () {
    final scan = IdCardParser.parse('Arjun Menon\n9876543210\n12/05/2026');
    expect(scan.regNo, isNull);
  });
}
