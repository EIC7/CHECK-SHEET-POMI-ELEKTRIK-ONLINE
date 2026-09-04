// ============================================================
//  Firebase Configuration — ELECTRIC 7 POMI
//  PENTING: Ganti nilai di bawah dengan config dari Firebase Console Anda
//  1. Buka https://console.firebase.google.com
//  2. Buat project baru (atau pakai yang sudah ada)
//  3. Tambahkan Web App
//  4. Copy firebaseConfig dan paste di bawah
//  5. Aktifkan Firestore Database di Firebase Console
// ============================================================

const firebaseConfig = {
  apiKey: "AIzaSyDXEMaTgz3DDM8DtJyrk5p46vQLW-gFZIc",
  authDomain: "database-eic7.firebaseapp.com",
  projectId: "database-eic7",
  storageBucket: "database-eic7.firebasestorage.app",
  messagingSenderId: "221856009931",
  appId: "1:221856009931:web:7b3a3c088d579fdc41554e"
};

firebase.initializeApp(firebaseConfig);
const db = firebase.firestore();
