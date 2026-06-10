USE fp_rental_kendaraan;

-- =====================================================
-- PEKERJAAN 7 - DATABASE TRANSACTION
-- Case: Transaksi penyewaan kendaraan aman anti-fraud
-- =====================================================

START TRANSACTION;

-- 1. Ambil pelanggan aktif yang tidak masuk blacklist terverifikasi
SELECT p.id_pelanggan
INTO @id_pelanggan
FROM pelanggan p
LEFT JOIN daftar_hitam dh
    ON p.nik = dh.nik
    AND dh.status_verifikasi = 'Terverifikasi'
WHERE p.status_akun = 'Aktif'
  AND dh.nik IS NULL
LIMIT 1;

-- 2. Ambil kendaraan yang tersedia dan lock barisnya
-- FOR UPDATE digunakan agar kendaraan yang sama tidak dipilih transaksi lain
SELECT k.id_kendaraan
INTO @id_kendaraan
FROM kendaraan k
WHERE k.status_kendaraan = 'Tersedia'
LIMIT 1
FOR UPDATE;

-- 3. Ambil tarif kendaraan untuk menghitung total harga
SELECT kk.tarif_harian
INTO @tarif_harian
FROM kendaraan k
JOIN kategori_kendaraan kk ON k.id_kategori = kk.id_kategori
WHERE k.id_kendaraan = @id_kendaraan;

-- 4. Hitung total harga sewa 2 hari
SET @durasi_hari = 2;
SET @total_harga = @tarif_harian * @durasi_hari;

-- 5. Cek data yang akan dipakai
SELECT
    @id_pelanggan AS id_pelanggan_dipakai,
    @id_kendaraan AS id_kendaraan_dipakai,
    @tarif_harian AS tarif_harian,
    @durasi_hari AS durasi_hari,
    @total_harga AS total_harga;

-- 6. Buat kontrak sewa baru
INSERT INTO kontrak_sewa (
    id_pelanggan,
    id_kendaraan,
    tanggal_ambil,
    tanggal_kembali_rencana,
    tanggal_kembali_aktual,
    total_harga,
    status_sewa
)
VALUES (
    @id_pelanggan,
    @id_kendaraan,
    NOW(),
    DATE_ADD(NOW(), INTERVAL @durasi_hari DAY),
    NULL,
    @total_harga,
    'Aktif'
);

SET @id_sewa_baru = LAST_INSERT_ID();

-- 7. Simpan dokumen jaminan KTP dan SIM
INSERT INTO dokumen_jaminan (
    id_sewa,
    jenis_dokumen,
    nomor_dokumen,
    kondisi_penyimpanan,
    lokasi_loker,
    waktu_serah_terima
)
VALUES
(
    @id_sewa_baru,
    'KTP',
    CONCAT('KTP-TRX-', @id_sewa_baru),
    'Dokumen fisik diterima dan disimpan dalam map jaminan',
    CONCAT('Loker-', @id_sewa_baru),
    NOW()
),
(
    @id_sewa_baru,
    'SIM',
    CONCAT('SIM-TRX-', @id_sewa_baru),
    'Dokumen fisik diterima dan disimpan dalam map jaminan',
    CONCAT('Loker-', @id_sewa_baru),
    NOW()
);

-- 8. Buat konfigurasi geofence radius 25 km
INSERT INTO konfigurasi_geofence (
    id_sewa,
    pusat_latitude,
    pusat_longitude,
    radius_km,
    batas_poligon,
    status_aktif
)
VALUES (
    @id_sewa_baru,
    -7.25750000,
    112.75210000,
    25.00,
    NULL,
    1
);

-- 9. Catat pembayaran awal
INSERT INTO pembayaran (
    id_sewa,
    tanggal_bayar,
    nominal,
    metode_pembayaran,
    status_pembayaran
)
VALUES (
    @id_sewa_baru,
    NOW(),
    @total_harga,
    'Transfer Bank',
    'Lunas'
);

-- 10. Insert inspeksi pra-sewa
INSERT INTO inspeksi_kendaraan (
    id_sewa,
    tipe_inspeksi,
    waktu_inspeksi,
    url_foto_1,
    url_foto_2,
    deskripsi_kondisi,
    id_petugas,
    hash_dokumen
)
VALUES (
    @id_sewa_baru,
    'Pra-Sewa',
    NOW(),
    'foto_pra_1.jpg',
    'foto_pra_2.jpg',
    'Kondisi kendaraan baik sebelum disewa. Tidak ditemukan lecet besar.',
    101,
    SHA2(CONCAT('PRA-SEWA-', @id_sewa_baru, NOW()), 256)
);

-- 11. Update status kendaraan
UPDATE kendaraan
SET status_kendaraan = 'Sedang Disewa'
WHERE id_kendaraan = @id_kendaraan;

COMMIT;

-- 12. Bukti hasil transaksi
SELECT
    ks.id_sewa,
    ks.status_sewa,
    ks.tanggal_ambil,
    ks.tanggal_kembali_rencana,
    p.nik,
    CONCAT(p.nama_depan, ' ', p.nama_belakang) AS nama_pelanggan,
    k.plat_nomor,
    k.status_kendaraan,
    kg.radius_km,
    pb.nominal,
    pb.status_pembayaran
FROM kontrak_sewa ks
JOIN pelanggan p ON ks.id_pelanggan = p.id_pelanggan
JOIN kendaraan k ON ks.id_kendaraan = k.id_kendaraan
LEFT JOIN konfigurasi_geofence kg ON ks.id_sewa = kg.id_sewa
LEFT JOIN pembayaran pb ON ks.id_sewa = pb.id_sewa
WHERE ks.id_sewa = @id_sewa_baru;

SELECT *
FROM dokumen_jaminan
WHERE id_sewa = @id_sewa_baru;

SELECT *
FROM inspeksi_kendaraan
WHERE id_sewa = @id_sewa_baru;