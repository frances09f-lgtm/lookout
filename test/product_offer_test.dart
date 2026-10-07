import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/page_fetch.dart';
void main(){
 String page(List<Map> products)=>'<script type="application/ld+json">${jsonEncode(products)}</script>';
 Map product({String price='54900',String url='https://shop.test/phone'})=>{'@type':'Product','name':'Exact phone','url':url,'offers':{'@type':'Offer','price':price,'priceCurrency':'INR'}};
 test('large product offer before budget survives unrelated prices',(){final p=page([product()])+List.filled(3000000,'x').join()+'₹180';expect(PageValueFetcher.productOffer(p,'https://shop.test/phone').price,54900);});
 test('empty offer never falls back to MRP or marketing',(){final p=page([product(price:'')])+'MRP ₹59900 Other product ₹180';final r=PageValueFetcher.productOffer(p,'https://shop.test/phone');expect(r.productPage,true);expect(r.price,isNull);});
 test('other product URL not accepted',(){expect(PageValueFetcher.productOffer(page([product(url:'https://shop.test/other')]),'https://shop.test/phone').price,isNull);});
 test('conflicting exact offers no guess',(){expect(PageValueFetcher.productOffer(page([product(),product(price:'59900')]),'https://shop.test/phone').price,isNull);});
 test('zero or absent currency unavailable',(){expect(PageValueFetcher.productOffer(page([product(price:'0')]),'https://shop.test/phone').price,isNull);});
}
