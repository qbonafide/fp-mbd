USE fp_rental_kendaraan;

DROP TRIGGER IF EXISTS trg_after_pelanggaran_geofence_insert;

DELIMITER $$

CREATE TRIGGER trg_after_pelanggaran_geofence_insert
AFTER INSERT ON pelanggaran_geofence
FOR EACH ROW
BEGIN
    DECLARE v_total_pelanggaran INT DEFAULT 0;
    DECLARE v_skor_risiko INT DEFAULT 0;
    DECLARE v_id_pelanggan INT;

    SELECT COUNT(*)
    INTO v_total_pelanggaran
    FROM pelanggaran_geofence
    WHERE id_sewa = NEW.id_sewa;

    SELECT id_pelanggan
    INTO v_id_pelanggan
    FROM kontrak_sewa
    WHERE id_sewa = NEW.id_sewa;

    SET v_skor_risiko =
        CASE
            WHEN NEW.jarak_pelanggaran_km >= 50 THEN 90
            WHEN NEW.jarak_pelanggaran_km >= 25 THEN 70
            WHEN NEW.jarak_pelanggaran_km >= 10 THEN 50
            ELSE 30
        END;

    SET v_skor_risiko = v_skor_risiko + (v_total_pelanggaran * 5);

    IF v_skor_risiko > 100 THEN
        SET v_skor_risiko = 100;
    END IF;

    INSERT INTO log_anomali (
        id_sewa,
        jenis_anomali,
        waktu_log,
        deskripsi,
        skor_risiko,
        status_tindak_lanjut
    )
    VALUES (
        NEW.id_sewa,
        'Pelanggaran Geofence',
        NEW.waktu_pelanggaran,
        CONCAT(
            'Pelanggaran geofence terdeteksi otomatis. Kendaraan ID ',
            NEW.id_kendaraan,
            ' keluar dari batas wilayah sejauh ',
            NEW.jarak_pelanggaran_km,
            ' km. Total pelanggaran pada kontrak ini: ',
            v_total_pelanggaran,
            '. Lokasi valid terakhir: ',
            NEW.lokasi_valid_terakhir,
            '. Lokasi pelanggaran: ',
            NEW.lokasi_pelanggaran,
            '. Status penanganan: ',
            NEW.status_penanganan
        ),
        v_skor_risiko,
        CASE
            WHEN v_skor_risiko >= 90 THEN 'Prioritas Tinggi'
            WHEN v_skor_risiko >= 70 THEN 'Perlu Ditinjau'
            ELSE 'Terbuka'
        END
    );

    IF v_skor_risiko >= 90 OR v_total_pelanggaran >= 3 THEN
        UPDATE kontrak_sewa
        SET status_sewa = 'Macet-Hukum'
        WHERE id_sewa = NEW.id_sewa;

        UPDATE pelanggan
        SET status_akun = 'Ditangguhkan'
        WHERE id_pelanggan = v_id_pelanggan;
    END IF;
END$$

DELIMITER ;