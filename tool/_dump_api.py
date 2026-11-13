import json

with open(r'C:\Users\admin\arab_drama_app\api-docs.json', encoding='utf-8-sig') as f:
    doc = json.load(f)

paths = doc.get('paths', {})
for key in ['/notice/google', '/api/pay/userRechange', '/api/pay/getOrderIsPay', '/api/user/userPersonalCenter']:
    print('=' * 30, key)
    print(json.dumps(paths.get(key), indent=2, ensure_ascii=False)[:2500])
