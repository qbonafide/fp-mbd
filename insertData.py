# =====================================================
# 1. IMPORT & KONEKSI DATABASE
# =====================================================
from faker import Faker
import mysql.connector
import random
from datetime import datetime, timedelta

# Inisialisasi Faker
fake = Faker('id_ID')

# Koneksi ke MySQL Laragon
db = mysql.connector.connect(
    host="127.0.0.1",
    user="root",
    password="",
    database="fp_rental_kendaraan"
)
cursor = db.cursor()
print("Koneksi Database Berhasil")
cursor.execute("SELECT DATABASE()")
print(cursor.fetchone())

# PARAMETER JUMLAH DATA
JUMLAH_CABANG = 20
JUMLAH_KATEGORI = 8
JUMLAH_KOMUNITAS = 50
JUMLAH_PELANGGAN = 200000
JUMLAH_KENDARAAN = 50000
JUMLAH_KONTRAK = 200000
JUMLAH_PEMBAYARAN = 200000
JUMLAH_DOKUMEN = 200000
JUMLAH_GEOFENCE = 200000
JUMLAH_INSPEKSI = 400000
JUMLAH_TRACKING = 500000
JUMLAH_ANOMALI = 5000
JUMLAH_PELANGGARAN = 20000
JUMLAH_BLACKLIST = 10000

# =====================================================
# 2. CABANG_RENTAL (20)
# =====================================================
def insert_cabang():
    print("INSERT CABANG RENTAL...")

    sql = """
    INSERT INTO cabang_rental
    (
        nama_cabang,
        alamat,
        no_telp
    )
    VALUES (%s,%s,%s)
    """
    kota = [
        "Surabaya",
        "Sidoarjo",
        "Malang",
        "Jakarta",
        "Bandung",
        "Semarang",
        "Yogyakarta",
        "Denpasar",
        "Medan",
        "Makassar",
        "Balikpapan",
        "Palembang",
        "Pontianak",
        "Manado",
        "Batam",
        "Bekasi",
        "Depok",
        "Bogor",
        "Solo",
        "Cirebon"
    ]
    data = []
    for i in range(JUMLAH_CABANG):
        data.append(
            (
                f"Cabang Rental {kota[i]}",
                fake.address(),
                f"08{random.randint(100000000,999999999)}"
            )
        )
    cursor.executemany(sql, data)
    db.commit()
    print("SELESAI CABANG RENTAL")

# =====================================================
# 3. KATEGORI_KENDARAAN (8)
# =====================================================
def insert_kategori():
    print("INSERT KATEGORI KENDARAAN...")

    sql = """
    INSERT INTO kategori_kendaraan
    (
        nama_kategori,
        tarif_harian,
        denda_keterlambatan_per_jam
    )
    VALUES (%s,%s,%s)
    """
    data = [
        ("SUV", 500000, 50000),
        ("MPV", 400000, 40000),
        ("Sedan", 350000, 35000),
        ("Hatchback", 300000, 30000),
        ("Pickup", 450000, 45000),
        ("Luxury", 1200000, 100000),
        ("Electric", 800000, 70000),
        ("Minibus", 700000, 60000)

    ]
    cursor.executemany(sql, data)
    db.commit()
    print("SELESAI KATEGORI KENDARAAN")

# =====================================================
# 4. KOMUNITAS_RENTAL (50)
# =====================================================
def insert_komunitas():
    print("INSERT KOMUNITAS RENTAL...")

    sql = """
    INSERT INTO komunitas_rental
    (
        nama_rental,
        kota,
        kontak,
        api_key,
        status_keanggotaan,
        tanggal_bergabung
    )
    VALUES (%s,%s,%s,%s,%s,%s)
    """
    data = []
    for i in range(JUMLAH_KOMUNITAS):
        status = random.choices(
            ['Aktif', 'Non-Aktif'],
            weights=[85,15]
        )[0]
        data.append(
            (
                f"Komunitas Rental Indonesia {i+1}",
                fake.city(),
                f"08{random.randint(100000000,999999999)}",
                fake.uuid4(),
                status,
                fake.date_between(
                    start_date='-10y',
                    end_date='today'
                )
            )
        )
    cursor.executemany(sql, data)
    db.commit()
    print("SELESAI KOMUNITAS RENTAL")

# =====================================================
# 5. PELANGGAN (200000)
# =====================================================
def insert_pelanggan():
    print("INSERT PELANGGAN...")

    sql = """
    INSERT INTO pelanggan
    (
        nik,
        nama_depan,
        nama_belakang,
        email,
        no_telp,
        no_sim,
        status_akun
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s)
    """
    batch = []
    for i in range(JUMLAH_PELANGGAN):
        status = random.choices(
            [
                'Aktif',
                'Ditangguhkan',
                'Diblokir'
            ],
            weights=[85,10,5]
        )[0]
        nik = str(1000000000000000 + i)
        nama_depan = fake.first_name()
        nama_belakang = fake.last_name()
        email = f"user{i}@gmail.com"
        no_telp = f"08{random.randint(100000000,999999999)}"
        no_sim = f"SIM{100000+i}"
        batch.append(
            (
                nik,
                nama_depan,
                nama_belakang,
                email,
                no_telp,
                no_sim,
                status
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql, batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql, batch)
        db.commit()
    print("SELESAI INSERT PELANGGAN")

# =====================================================
# 6. KENDARAAN (50000)
# =====================================================
def insert_kendaraan():
    print("INSERT KENDARAAN...")

    sql = """
    INSERT INTO kendaraan
    (
        id_kategori,
        id_cabang,
        merk,
        model,
        tahun_pembuatan,
        plat_nomor,
        kilometer_saat_ini,
        status_kendaraan
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
    """
    merk_model = {

        "Toyota": [
            "Avanza",
            "Innova",
            "Fortuner",
            "Raize"
        ],
        "Honda": [
            "Brio",
            "HRV",
            "CRV",
            "Mobilio"
        ],
        "Suzuki": [
            "Ertiga",
            "XL7",
            "Carry"
        ],
        "Daihatsu": [
            "Xenia",
            "Terios",
            "Sigra"
        ],
        "Mitsubishi": [
            "Xpander",
            "Pajero",
            "L300"
        ]
    }
    batch = []
    for i in range(JUMLAH_KENDARAAN):
        merk = random.choice(list(merk_model.keys()))
        model = random.choice(merk_model[merk])
        status = random.choices(
            [
                'Tersedia',
                'Sedang Disewa',
                'Perawatan',
                'Hilang',
                'Rusak'
            ],
            weights=[70,20,7,2,1]
        )[0]
        batch.append(
            (
                random.randint(1,8),      # kategori
                random.randint(1,20),     # cabang
                merk,
                model,
                random.randint(2018,2025),
                f"B{i:06d}XYZ",
                random.randint(0,200000),
                status
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql, batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql, batch)
        db.commit()
    print("SELESAI INSERT KENDARAAN")

# =====================================================
# 7. KONTRAK_SEWA (200000)
# =====================================================
def insert_kontrak():
    print("INSERT KONTRAK SEWA...")

    sql = """
    INSERT INTO kontrak_sewa
    (
        id_pelanggan,
        id_kendaraan,
        tanggal_ambil,
        tanggal_kembali_rencana,
        tanggal_kembali_aktual,
        total_harga,
        status_sewa
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s)
    """
    batch = []
    for i in range(JUMLAH_KONTRAK):
        tanggal_ambil = fake.date_time_between(
            start_date='-2y',
            end_date='now'
        )
        lama_sewa = random.randint(1,14)
        tanggal_kembali_rencana = (
            tanggal_ambil +
            timedelta(days=lama_sewa)
        )
        status = random.choices(
            [
                'Dipesan',
                'Aktif',
                'Selesai',
                'Dibatalkan',
                'Terlambat',
                'Macet-Hukum'
            ],
            weights=[10,20,55,5,8,2]
        )[0]
        tanggal_kembali_aktual = None
        if status in ['Selesai','Terlambat']:

            tanggal_kembali_aktual = (
                tanggal_kembali_rencana +
                timedelta(days=random.randint(0,5))
            )
        total_harga = random.randint(
            300000,
            5000000
        )
        batch.append(
            (
                random.randint(1,JUMLAH_PELANGGAN),
                random.randint(1,JUMLAH_KENDARAAN),
                tanggal_ambil,
                tanggal_kembali_rencana,
                tanggal_kembali_aktual,
                total_harga,
                status
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql,batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql,batch)
        db.commit()
    print("SELESAI INSERT KONTRAK")

# =====================================================
# 8. PEMBAYARAN (200000)
# =====================================================
def insert_pembayaran():
    print("INSERT PEMBAYARAN...")

    sql = """
    INSERT INTO pembayaran
    (
        id_sewa,
        tanggal_bayar,
        nominal,
        metode_pembayaran,
        status_pembayaran
    )
    VALUES (%s,%s,%s,%s,%s)
    """
    metode = [
        'Kartu Kredit',
        'Tunai',
        'Transfer Bank',
        'E-Wallet',
        'QRIS'
    ]
    batch = []
    for i in range(JUMLAH_PEMBAYARAN):
        status = random.choices(
            [
                'Lunas',
                'Pending',
                'Terlambat',
                'Menunggak'
            ],
            weights=[80,10,7,3]
        )[0]
        batch.append(
            (
                random.randint(1,JUMLAH_KONTRAK),
                fake.date_time_between(
                    start_date='-2y',
                    end_date='now'
                ),
                random.randint(
                    300000,
                    5000000
                ),
                random.choice(metode),
                status
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql,batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql,batch)
        db.commit()
    print("SELESAI INSERT PEMBAYARAN")

# =====================================================
# 9. DOKUMEN_JAMINAN (200000)
# =====================================================
def insert_dokumen():
    print("INSERT DOKUMEN JAMINAN...")

    sql = """
    INSERT INTO dokumen_jaminan
    (
        id_sewa,
        jenis_dokumen,
        nomor_dokumen,
        kondisi_penyimpanan,
        lokasi_loker,
        waktu_serah_terima
    )
    VALUES (%s,%s,%s,%s,%s,%s)
    """
    kondisi = [
        'Loker Aman',
        'Brankas Utama',
        'Arsip Digital'
    ]
    batch = []
    for i in range(JUMLAH_DOKUMEN):
        batch.append(
            (
                random.randint(1,JUMLAH_KONTRAK),
                random.choice([
                    'KTP',
                    'SIM',
                    'Paspor'
                ]),
                f"DOC{i+1}",
                random.choice(kondisi),
                f"LKR-{random.randint(1,500)}",
                fake.date_time_between(
                    start_date='-2y',
                    end_date='now'
                )
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql,batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql,batch)
        db.commit()
    print("SELESAI INSERT DOKUMEN")

# =====================================================
# 10. KONFIGURASI_GEOFENCE (200000)
# =====================================================
def insert_geofence():
    print("INSERT KONFIGURASI GEOFENCE...")
    
    sql = """
    INSERT INTO konfigurasi_geofence
    (
        id_sewa,
        pusat_latitude,
        pusat_longitude,
        radius_km,
        status_aktif
    )
    VALUES (%s,%s,%s,%s,%s,%s)
    """
    batch = []
    for id_sewa in range(1, JUMLAH_KONTRAK + 1):
        batch.append(
            (
                id_sewa,
                round(random.uniform(-8.8, -5.8), 8),
                round(random.uniform(106.0, 114.0), 8),
                random.choice([10,15,20,25,30,50]),
                1
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql, batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql, batch)
        db.commit()
    print("SELESAI INSERT GEOFENCE")

# =====================================================
# 11. INSPEKSI_KENDARAAN (400000)
# =====================================================
def insert_inspeksi():
    print("INSERT INSPEKSI KENDARAAN...")

    sql = """
    INSERT INTO inspeksi_kendaraan
    (
        id_sewa,
        tipe_inspeksi,
        waktu_inspeksi,
        url_foto_1,
        url_foto_2,
        deskripsi_kondisi,
        id_petugas,
        hash_dokumen
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
    """
    kondisi = [
        "Kendaraan dalam kondisi baik",
        "Terdapat baret ringan",
        "Ban depan mulai aus",
        "Kondisi sangat baik",
        "Perlu pengecekan rem",
        "Lampu belakang kurang terang"
    ]
    batch = []
    for id_sewa in range(1, JUMLAH_KONTRAK + 1):
        batch.append(
            (
                id_sewa,
                'Pra-Sewa',
                fake.date_time_between(
                    start_date='-2y',
                    end_date='now'
                ),
                f"https://img.rental/{id_sewa}_pre1.jpg",
                f"https://img.rental/{id_sewa}_pre2.jpg",
                random.choice(kondisi),
                random.randint(1,100),
                fake.sha256()
            )
        )
        batch.append(
            (
                id_sewa,
                'Pasca-Sewa',
                fake.date_time_between(
                    start_date='-2y',
                    end_date='now'
                ),
                f"https://img.rental/{id_sewa}_post1.jpg",
                f"https://img.rental/{id_sewa}_post2.jpg",
                random.choice(kondisi),
                random.randint(1,100),
                fake.sha256()
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql, batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql, batch)
        db.commit()
    print("SELESAI INSERT INSPEKSI")

# =====================================================
# 12. PELACAKAN_LOKASI (500000)
# =====================================================
def insert_tracking():
    print("INSERT PELACAKAN LOKASI...")

    sql = """
    INSERT INTO pelacakan_lokasi
    (
        id_kendaraan,
        waktu_log,
        latitude,
        longitude,
        kecepatan_kmj,
        status_sinyal,
        sumber_data
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s)
    """
    batch = []
    for i in range(JUMLAH_TRACKING):
        status_sinyal = random.choices(
            [
                'Kuat',
                'Lemah',
                'Hilang'
            ],
            weights=[95,3,2]
        )[0]
        batch.append(
            (
                random.randint(1, JUMLAH_KENDARAAN),
                fake.date_time_between(
                    start_date='-1y',
                    end_date='now'
                ),
                round(
                    random.uniform(-8.8, -5.8),
                    8
                ),
                round(
                    random.uniform(106.0, 114.0),
                    8
                ),
                random.randint(0,120),
                status_sinyal,
                random.choice([
                    'GPS',
                    'GSM',
                    'SIM_CARD'
                ])
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql, batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql, batch)
        db.commit()
    print("SELESAI INSERT TRACKING")

# =====================================================
# 13. LOG_ANOMALI (5000)
# =====================================================
def insert_anomali():
    print("INSERT LOG ANOMALI...")

    sql = """
    INSERT INTO log_anomali
    (
        id_sewa,
        jenis_anomali,
        waktu_log,
        deskripsi,
        skor_risiko,
        status_tindak_lanjut
    )
    VALUES (%s,%s,%s,%s,%s,%s)
    """
    batch = []
    jenis_anomali = [
        "GPS_HILANG",
        "GEOFENCE_BREACH",
        "TELAT_BAYAR",
        "KENDARAAN_TIDAK_KEMBALI",
        "PEMBAYARAN_MENCURIGAKAN"
    ]
    for i in range(JUMLAH_ANOMALI):
        jenis = random.choice(jenis_anomali)
        batch.append(
            (
                random.randint(1, JUMLAH_KONTRAK),
                jenis,
                fake.date_time_between(
                    start_date='-1y',
                    end_date='now'
                ),
                f"Deteksi otomatis anomali {jenis}",
                random.randint(20,100),
                random.choice([
                    "Terbuka",
                    "Diproses",
                    "Selesai"
                ])
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql,batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql,batch)
        db.commit()
    print("SELESAI INSERT LOG ANOMALI")

# =====================================================
# 14. PELANGGARAN_GEOFENCE (20000)
# =====================================================
def insert_pelanggaran_geofence():
    print("INSERT PELANGGARAN GEOFENCE...")

    sql = """
    INSERT INTO pelanggaran_geofence
    (
        id_kendaraan,
        id_sewa,
        waktu_pelanggaran,
        lokasi_valid_terakhir,
        lokasi_pelanggaran,
        jarak_pelanggaran_km,
        status_penanganan
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s)
    """
    batch = []
    for i in range(JUMLAH_PELANGGARAN):
        batch.append(
            (
                random.randint(1, JUMLAH_KENDARAAN),
                random.randint(1, JUMLAH_KONTRAK),
                fake.date_time_between(
                    start_date='-1y',
                    end_date='now'
                ),
                fake.city(),
                fake.city(),
                round(
                    random.uniform(5,100),
                    2
                ),
                random.choice([
                    'Belum Diproses',
                    'Diperingatkan',
                    'Mesin Dimatikan'
                ])
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql,batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql,batch)
        db.commit()
    print("SELESAI INSERT PELANGGARAN GEOFENCE")

# =====================================================
# 15. DAFTAR_HITAM (10000)
# =====================================================
def insert_blacklist():
    print("INSERT DAFTAR HITAM...")

    sql = """
    INSERT INTO daftar_hitam
    (
        nik,
        nama_lengkap,
        url_foto_wajah,
        jenis_pelanggaran,
        tanggal_kejadian,
        id_rental_pelapor,
        status_verifikasi
    )
    VALUES (%s,%s,%s,%s,%s,%s,%s)
    """
    pelanggaran = [
        "Penggelapan Kendaraan",
        "Pemalsuan Dokumen",
        "Menunggak Pembayaran",
        "Merusak Kendaraan",
        "Melewati Geofence"
    ]
    batch = []
    for i in range(JUMLAH_BLACKLIST):
        nik_blacklist = str(
            1000000000000000 +
            random.randint(
                0,
                JUMLAH_PELANGGAN - 1
            )
        )
        batch.append(
            (
                nik_blacklist,
                fake.name(),
                f"https://img.blacklist/{i}.jpg",
                random.choice(pelanggaran),
                fake.date_between(
                    start_date='-5y',
                    end_date='today'
                ),
                random.randint(
                    1,
                    JUMLAH_KOMUNITAS
                ),
                random.choice([
                    'Menunggu',
                    'Terverifikasi'
                ])
            )
        )
        if len(batch) >= 1000:
            cursor.executemany(sql, batch)
            db.commit()
            batch.clear()
    if batch:
        cursor.executemany(sql, batch)
        db.commit()
    print("SELESAI INSERT DAFTAR HITAM")

# =====================================================
# MAIN EXECUTION
# =====================================================
if __name__ == "__main__":
    insert_cabang()
    insert_kategori()
    insert_komunitas()
    insert_pelanggan()
    insert_kendaraan()
    insert_kontrak()
    insert_geofence()
    insert_dokumen()
    insert_pembayaran()
    insert_inspeksi()
    insert_tracking()
    insert_anomali()
    insert_pelanggaran_geofence()
    insert_blacklist()
    print("SEMUA DATA BERHASIL DIINSERT")
