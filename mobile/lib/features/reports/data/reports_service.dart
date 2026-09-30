/// Liste de signalements de démonstration. Utilisée seulement par
/// `ReportsScreen` et ses tests, pas par l'app.
abstract interface class ReportsService {
  Future<List<String>> fetchReports();
}
