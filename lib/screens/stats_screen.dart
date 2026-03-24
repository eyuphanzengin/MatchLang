import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_data_provider.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        title: const Text("İstatistikler & Liderlik"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: "İstatistiklerim"),
            Tab(text: "Liderlik Tablosu"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_MyStatsTab(), _LeaderboardTab()],
      ),
    );
  }
}

class _MyStatsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final userData = context.watch<UserDataProvider>();
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Günlük Seri Başlığı
            Text(
              "GÜNLÜK SERİ",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),

            // Büyük Ateş İkonu ve Sayaç
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    strokeWidth: 10,
                    color: Colors.grey.shade800,
                  ),
                ),
                Column(
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: Colors.orange,
                      size: 50,
                    ),
                    Text(
                      "${userData.todaysCorrectAnswers > 0 ? 1 : 0}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Seviye Kutusu
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "Seviye ${userData.currentLevel}",
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

            const SizedBox(height: 40),

            // İstatistik Kartları (Doğru/Yanlış vb.)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard(
                  "Doğru",
                  "${userData.todaysCorrectAnswers}",
                  Colors.green,
                ),
                _buildStatCard(
                  "Yanlış",
                  "${userData.todaysIncorrectAnswers}",
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withAlpha(100), width: 2),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: context.read<UserDataProvider>().leaderboardStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Hata: ${snapshot.error}",
              style: const TextStyle(color: Colors.white),
            ),
          );
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return const Center(
            child: Text(
              "Liderlik tablosu boş",
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        return ListView.builder(
          itemCount: users.length,
          padding: const EdgeInsets.all(16),
          itemBuilder: (context, index) {
            final user = users[index];
            final score = user['score'] ?? 0;
            final isTop3 = index < 3;

            return Card(
              color: isTop3
                  ? Colors.amber.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isTop3 ? Colors.amber : Colors.grey,
                  child: Text(
                    "${index + 1}",
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  "${user['userName'] ?? user['email'] ?? 'Kullanıcı'}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: isTop3
                    ? const Text(
                        "🏆 Gelecek hafta üst lige yükselecek!",
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                        ),
                      )
                    : null,
                trailing: Text(
                  "$score P",
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
