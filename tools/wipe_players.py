"""Sterge toti jucatorii in afara de contul Google al adminului.
python wipe_players.py          -> doar arata ce ar sterge
python wipe_players.py --sterge -> sterge efectiv
"""
import os, sys, requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request
from google.cloud import firestore

os.chdir(r"D:\proiecte\SodoQuizz")
SA = "tools/service-account.json"
KEEP = "GaIygBrfy"  # prefix; rezolvat mai jos la uid-ul complet
APPLY = "--sterge" in sys.argv

db = firestore.Client(project="sodoquizz", credentials=service_account.Credentials.from_service_account_file(SA))
ac = service_account.Credentials.from_service_account_file(
    SA, scopes=["https://www.googleapis.com/auth/identitytoolkit", "https://www.googleapis.com/auth/cloud-platform"])
ac.refresh(Request())
H = {"Authorization": f"Bearer {ac.token}"}
IT = "https://identitytoolkit.googleapis.com/v1/projects/sodoquizz"

auth, tok = {}, None
while True:
    r = requests.get(f"{IT}/accounts:batchGet", headers=H,
                     params={"maxResults": 500, **({"nextPageToken": tok} if tok else {})}, timeout=60).json()
    for u in r.get("users", []):
        auth[u["localId"]] = u.get("email", "")
    tok = r.get("nextPageToken")
    if not tok: break

keep = [u for u, e in auth.items() if e == "dragosssx@gmail.com"]
assert len(keep) == 1, f"contul admin nu e unic in Auth: {keep}"
keep = keep[0]

profiles = {d.id for d in db.collection("player_profiles").stream()}
saves = {d.id for d in db.collection("users").stream()}
victims = (set(auth) | profiles | saves) - {keep}
print(f"PASTREZ: {keep} (dragosssx@gmail.com)")
print(f"STERG:   {len(victims)} jucatori  (Auth: {len(set(auth)-{keep})}, profiluri: {len(profiles-{keep})}, cloud-save: {len(saves-{keep})})")

# resturi care ii mentioneaza pe cei stersi, in afara documentelor lor
extra = []
for sub in db.collection("player_profiles").document(keep).collections():
    for d in sub.stream():
        if d.id in victims:
            extra.append(d.reference)
for coll in ["challenges", "rematch_offers"]:
    for d in db.collection(coll).stream():
        vals = " ".join(str(v) for v in d.to_dict().values())
        if any(v in vals or v == d.id for v in victims):
            extra.append(d.reference)
print(f"RESTURI: {len(extra)} document(e) care trimit la jucatori stersi: " + ", ".join(r.path for r in extra))

if not APPLY:
    print("\nProba. Nimic sters.")
    sys.exit(0)

for uid in sorted(victims):
    for ref in [db.collection("player_profiles").document(uid), db.collection("users").document(uid)]:
        db.recursive_delete(ref)
    for coll in ["admin_grants", "banned_players", "multiplayer_presence", "pending_auth_deletions"]:
        db.collection(coll).document(uid).delete()
for ref in extra:
    db.recursive_delete(ref)
ids = sorted(set(auth) & victims)
for i in range(0, len(ids), 100):
    r = requests.post(f"{IT}/accounts:batchDelete", headers=H, json={"localIds": ids[i:i+100], "force": True}, timeout=60)
    r.raise_for_status()
    errs = r.json().get("errors", [])
    print(f"Auth: {len(ids[i:i+100]) - len(errs)} sterse, {len(errs)} erori {errs if errs else ''}")

left_p = {d.id for d in db.collection("player_profiles").stream()}
left_s = {d.id for d in db.collection("users").stream()}
print(f"\nVERIFICARE: profiluri ramase {sorted(left_p)} | cloud-save ramase {sorted(left_s)}")
