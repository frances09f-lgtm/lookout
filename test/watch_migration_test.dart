import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lookout/data/sqflite_repository.dart';
void main(){test('v2 to v3 retains watch and adds unknown provenance',()async{
 sqfliteFfiInit();databaseFactory=databaseFactoryFfi;final dir=await Directory.systemTemp.createTemp();final path='${dir.path}/old.db';
 final old=await openDatabase(path,version:2,onCreate:(db,_)async{
 await db.execute('CREATE TABLE agents(id INTEGER PRIMARY KEY, title TEXT, originalPrompt TEXT, type TEXT, status TEXT, createdAt INTEGER, lastCheckedAt INTEGER, nextCheckAt INTEGER, checkIntervalMinutes INTEGER, condition TEXT, target REAL, currentValue REAL, previousValue REAL, sourceUrl TEXT, notificationEnabled INTEGER)');
 await db.execute("INSERT INTO agents VALUES(1,'Existing watch','Watch price','valueWatch','active',1,2,3,30,'lessThan',100,150,160,'https://example.com',1)");
 });await old.close();final repo=await SqfliteAgentRepository.open(path:path);final a=(await repo.agentById(1))!;expect(a.currentValue,150);expect(a.target,100);expect(a.lastSuccessfulReadAt,isNull);await repo.updateAgent(a.copyWith(lastSuccessfulReadAt:DateTime(2026),lastSuccessfulValue:150,lastReadMethod:'Automatic page read',lastReadSourceUrl:a.sourceUrl));expect((await repo.agentById(1))!.lastReadMethod,'Automatic page read');await repo.close();await dir.delete(recursive:true);
 });}
