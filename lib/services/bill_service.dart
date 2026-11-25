import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bill_model.dart';

/// Serviço de contas mensais usando Firestore (sincronização em tempo real)
class BillService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'bills';

  /// Stream em tempo real de contas do mês/ano especificado
  Stream<List<Bill>> getBillsStream(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);

    return _firestore
        .collection(_collection)
        .where('dueDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('dueDate')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Bill.fromFirestore(doc)).toList());
  }

  /// Adiciona nova conta
  Future<void> addBill(Bill bill) async {
    await _firestore.collection(_collection).add(bill.toFirestore());
  }

  /// Alterna status pago/pendente (sincronizado para todos os usuários)
  Future<void> togglePaid(String billId, bool isPaid, String paidBy) async {
    await _firestore.collection(_collection).doc(billId).update({
      'isPaid': isPaid,
      'paidBy': isPaid ? paidBy : null,
    });
  }

  /// Atualiza uma conta
  Future<void> updateBill(Bill bill) async {
    await _firestore
        .collection(_collection)
        .doc(bill.id)
        .update(bill.toFirestore());
  }

  /// Remove uma conta
  Future<void> deleteBill(String billId) async {
    await _firestore.collection(_collection).doc(billId).delete();
  }
}
