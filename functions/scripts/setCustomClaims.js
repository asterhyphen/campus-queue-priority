const admin = require('firebase-admin');

if (process.argv.length < 4) {
  console.error('Usage: node setCustomClaims.js <uid> <role>');
  process.exit(1);
}

const uid = process.argv[2];
const role = process.argv[3];

admin.initializeApp();

admin.auth().setCustomUserClaims(uid, { role }).then(() => {
  console.log(`Custom claims set for ${uid} -> role=${role}`);
  process.exit(0);
}).catch(err => {
  console.error('Failed to set custom claims', err);
  process.exit(1);
});
