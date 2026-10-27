import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/claim_model.dart';
import '../../providers/app_state.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Campus Moderation Panel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Submitted Ownership Claims', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...appState.claims.map(
            (c) => Card(
              child: ListTile(
                title: Text('Claimant: ${c.claimantName}'),
                subtitle: Text('Proof: ${c.privateClaimDetails}\nStatus: ${c.status.name.toUpperCase()}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => appState.reviewClaim(c.id, ClaimStatus.rejected)),
                    IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => appState.reviewClaim(c.id, ClaimStatus.approved)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
