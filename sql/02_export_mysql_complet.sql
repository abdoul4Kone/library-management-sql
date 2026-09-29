-- phpMyAdmin SQL Dump
-- version 4.9.2
-- https://www.phpmyadmin.net/
--
-- Hôte : 127.0.0.1:3308
-- Export phpMyAdmin historique; le script de référence est 01_schema_triggers_procedures.sql.
-- Généré le :  Dim 06 avr. 2025 à 06:37
-- Version du serveur :  5.7.28
-- Version de PHP :  7.3.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de données :  `bibliotecho`
--

DELIMITER $$
--
-- Procédures
--
DROP PROCEDURE IF EXISTS `enregistrer_retour`$$
CREATE PROCEDURE `enregistrer_retour` (IN `p_id_emprunt` INT, IN `p_date_retour` DATE)  BEGIN
    DECLARE v_retard INT;
    DECLARE v_id_adherent INT;
    DECLARE v_penalite DECIMAL(10,2);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Calculer le retard en jours
    SELECT DATEDIFF(p_date_retour, DateRetourPrevue), IdAdherent 
    INTO v_retard, v_id_adherent
    FROM Emprunt
    WHERE IdEmprunt = p_id_emprunt;
    
    -- Mettre à jour l'emprunt
    UPDATE Emprunt 
    SET DateRetourEffective = p_date_retour,
        Penalite = CASE WHEN v_retard > 0 THEN v_retard * 500 ELSE 0 END
    WHERE IdEmprunt = p_id_emprunt;
    
    -- Si retard, enregistrer la pénalité
    IF v_retard > 0 THEN
        SET v_penalite = v_retard * 500;
        
        INSERT INTO Penalite (IdAdherent, IdEmprunt, Montant, DatePenalite, Statut)
        VALUES (v_id_adherent, p_id_emprunt, v_penalite, CURDATE(), 'En Attente');
    END IF;
    
    COMMIT;
END$$

DROP PROCEDURE IF EXISTS `supprimer_exemplaire_egare`$$
CREATE PROCEDURE `supprimer_exemplaire_egare` (IN `p_id_exemplaire` INT, IN `p_id_adherent` INT)  BEGIN
    DECLARE v_isbn VARCHAR(13);
    DECLARE v_valeur DECIMAL(10,2);
    DECLARE v_id_emprunt INT DEFAULT NULL;
    DECLARE v_statut VARCHAR(20);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    

    -- La perte doit correspondre à un emprunt actif de cet adhérent.
    SELECT em.IdEmprunt, ex.ISBN, l.Valeur, ex.Statut
    INTO v_id_emprunt, v_isbn, v_valeur, v_statut
    FROM Emprunt em
    JOIN Exemplaire ex ON ex.IdExemplaire = em.IdExemplaire
    JOIN Livre l ON ex.ISBN = l.ISBN
    WHERE em.IdExemplaire = p_id_exemplaire
      AND em.IdAdherent = p_id_adherent
      AND em.DateRetourEffective IS NULL
    FOR UPDATE;

    IF v_id_emprunt IS NULL OR v_statut <> 'Emprunté' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Aucun emprunt actif de cet exemplaire pour cet adhérent';
    END IF;
    
    -- Enregistrer la pénalité liée à l'emprunt.
    INSERT INTO Penalite (IdAdherent, IdEmprunt, Montant, DatePenalite, Statut)
    VALUES (p_id_adherent, v_id_emprunt, v_valeur, CURDATE(), 'En Attente');
    
    -- Clôturer l'emprunt puis conserver la copie pour préserver l'historique.
    UPDATE Emprunt
    SET DateRetourEffective = CURDATE(), Penalite = v_valeur
    WHERE IdEmprunt = v_id_emprunt;

    UPDATE Exemplaire
    SET Statut = 'Perdu'
    WHERE IdExemplaire = p_id_exemplaire;
    
    -- Le déclencheur de retour rend la copie disponible juste avant sa perte.
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal - 1,
      NombreExemplairesDisponibles = NombreExemplairesDisponibles - 1
    WHERE ISBN = v_isbn;
    
    COMMIT;
END$$

DROP PROCEDURE IF EXISTS `traiter_reservations_expirees`$$
CREATE PROCEDURE `traiter_reservations_expirees` ()  BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_isbn VARCHAR(13);
    DECLARE cur CURSOR FOR 
        SELECT DISTINCT ISBN FROM Reservation
        WHERE Statut = 'Notifiée' AND DateLimiteRecuperation < CURDATE();
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;

    -- Traiter la file avant de supprimer les réservations expirées.
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_isbn;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Notifier la prochaine réservation en attente
    UPDATE Reservation
    SET Statut = 'Expirée'
    WHERE ISBN = v_isbn
      AND Statut = 'Notifiée'
      AND DateLimiteRecuperation < CURDATE();

    IF EXISTS (
      SELECT 1 FROM Livre
      WHERE ISBN = v_isbn AND NombreExemplairesDisponibles > 0
    ) THEN
        UPDATE Reservation
        SET Statut = 'Notifiée',
            DateLimiteRecuperation = DATE_ADD(CURDATE(), INTERVAL 3 DAY)
        WHERE ISBN = v_isbn
        AND Statut = 'En Attente'
        AND IdReservation = (
            SELECT prochaine.IdReservation
            FROM (
              SELECT r.IdReservation
              FROM Reservation r
              WHERE r.ISBN = v_isbn AND r.Statut = 'En Attente'
              ORDER BY r.DateReservation, r.IdReservation
              LIMIT 1
            ) AS prochaine
        );
          END IF;
    END LOOP;
    CLOSE cur;

    DELETE FROM Reservation
    WHERE Statut = 'Expirée' AND DateLimiteRecuperation < CURDATE();
    
    COMMIT;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `abonnement`
--

DROP TABLE IF EXISTS `abonnement`;
CREATE TABLE IF NOT EXISTS `abonnement` (
  `IdAbonnement` int(11) NOT NULL AUTO_INCREMENT,
  `IdAdherent` int(11) NOT NULL,
  `DateDebut` date NOT NULL,
  `DateFin` date NOT NULL,
  `Montant` decimal(10,2) NOT NULL DEFAULT '5000.00',
  `Statut` enum('Actif','Expiré') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Actif',
  PRIMARY KEY (`IdAbonnement`),
  KEY `IdAdherent` (`IdAdherent`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `abonnement`
--

INSERT INTO `abonnement` (`IdAbonnement`, `IdAdherent`, `DateDebut`, `DateFin`, `Montant`, `Statut`) VALUES
(1, 1, CURDATE(), LAST_DAY(CURDATE()), '5000.00', 'Actif'),
(2, 2, CURDATE(), LAST_DAY(CURDATE()), '5000.00', 'Actif'),
(3, 3, CURDATE(), LAST_DAY(CURDATE()), '5000.00', 'Actif'),
(4, 4, CURDATE(), LAST_DAY(CURDATE()), '5000.00', 'Actif'),
(5, 5, CURDATE(), LAST_DAY(CURDATE()), '5000.00', 'Actif');

-- --------------------------------------------------------

--
-- Structure de la table `adherent`
--

DROP TABLE IF EXISTS `adherent`;
CREATE TABLE IF NOT EXISTS `adherent` (
  `IdAdherent` int(11) NOT NULL AUTO_INCREMENT,
  `Nom` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Prenom` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Adresse` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Telephone` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `DateInscription` date NOT NULL,
  `AbonnementActif` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`IdAdherent`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `adherent`
--

INSERT INTO `adherent` (`IdAdherent`, `Nom`, `Prenom`, `Adresse`, `Telephone`, `DateInscription`, `AbonnementActif`) VALUES
(1, 'Membre', 'Test 1', 'Adresse fictive 1', '0000000001', '2023-01-10', 1),
(2, 'Membre', 'Test 2', 'Adresse fictive 2', '0000000002', '2023-02-15', 1),
(3, 'Membre', 'Test 3', 'Adresse fictive 3', '0000000003', '2023-03-20', 1),
(4, 'Membre', 'Test 4', 'Adresse fictive 4', '0000000004', '2023-04-25', 1),
(5, 'Membre', 'Test 5', 'Adresse fictive 5', '0000000005', '2023-05-30', 1);

-- --------------------------------------------------------

--
-- Structure de la table `auteur`
--

DROP TABLE IF EXISTS `auteur`;
CREATE TABLE IF NOT EXISTS `auteur` (
  `IdAuteur` int(11) NOT NULL AUTO_INCREMENT,
  `Nom` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Prenom` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Nationalite` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  PRIMARY KEY (`IdAuteur`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `auteur`
--

INSERT INTO `auteur` (`IdAuteur`, `Nom`, `Prenom`, `Nationalite`) VALUES
(1, 'Hugo', 'Victor', 'Française'),
(2, 'Orwell', 'George', 'Britannique'),
(3, 'Asimov', 'Isaac', 'Américaine'),
(4, 'Rowling', 'J.K.', 'Britannique'),
(5, 'Christie', 'Agatha', 'Britannique');

-- --------------------------------------------------------

--
-- Structure de la table `emprunt`
--

DROP TABLE IF EXISTS `emprunt`;
CREATE TABLE IF NOT EXISTS `emprunt` (
  `IdEmprunt` int(11) NOT NULL AUTO_INCREMENT,
  `IdAdherent` int(11) NOT NULL,
  `IdExemplaire` int(11) NOT NULL,
  `DateDebut` date NOT NULL,
  `DateRetourPrevue` date NOT NULL,
  `DateRetourEffective` date DEFAULT NULL,
  `Penalite` decimal(10,2) DEFAULT '0.00',
  PRIMARY KEY (`IdEmprunt`),
  KEY `IdAdherent` (`IdAdherent`),
  KEY `IdExemplaire` (`IdExemplaire`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `emprunt`
--

INSERT INTO `emprunt` (`IdEmprunt`, `IdAdherent`, `IdExemplaire`, `DateDebut`, `DateRetourPrevue`, `DateRetourEffective`, `Penalite`) VALUES
(1, 1, 1, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_SUB(CURDATE(), INTERVAL 3 DAY), '1000.00'),
(2, 1, 4, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_SUB(CURDATE(), INTERVAL 3 DAY), '1000.00'),
(3, 2, 6, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), '0.00'),
(4, 3, 8, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), '0.00'),
(5, 5, 11, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), '0.00'),
(6, 2, 2, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), CURDATE(), '25.00'),
(7, 3, 12, DATE_SUB(CURDATE(), INTERVAL 20 DAY), DATE_SUB(CURDATE(), INTERVAL 5 DAY), CURDATE(), '15.00');

--
-- Déclencheurs `emprunt`
--
DROP TRIGGER IF EXISTS `ajout_question_2`;
DELIMITER $$
CREATE TRIGGER `ajout_question_2` AFTER INSERT ON `emprunt` FOR EACH ROW BEGIN
    UPDATE Exemplaire SET Statut = 'Emprunté' WHERE IdExemplaire = NEW.IdExemplaire;
    UPDATE Livre l JOIN Exemplaire e ON l.ISBN = e.ISBN
    SET l.NombreExemplairesDisponibles = l.NombreExemplairesDisponibles - 1
    WHERE e.IdExemplaire = NEW.IdExemplaire;
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `limite_emprunts_question_3`;
DELIMITER $$
CREATE TRIGGER `limite_emprunts_question_3` BEFORE INSERT ON `emprunt` FOR EACH ROW BEGIN
    DECLARE nb_emprunts INT;
    DECLARE abonnement_actif INT;
    DECLARE exemplaire_disponible INT;

    SELECT COUNT(*) INTO abonnement_actif
    FROM Abonnement
    WHERE IdAdherent = NEW.IdAdherent
      AND Statut = 'Actif'
      AND CURDATE() BETWEEN DateDebut AND DateFin;

    IF abonnement_actif = 0 THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Un abonnement actif est requis pour emprunter';
    END IF;

    IF NEW.DateRetourPrevue < NEW.DateDebut
       OR NEW.DateRetourPrevue > DATE_ADD(NEW.DateDebut, INTERVAL 15 DAY) THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'La durée d''un emprunt ne peut pas dépasser 15 jours';
    END IF;

    SELECT COUNT(*) INTO exemplaire_disponible
    FROM Exemplaire
    WHERE IdExemplaire = NEW.IdExemplaire AND Statut = 'Disponible';

    IF exemplaire_disponible = 0 THEN
      SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cet exemplaire n''est pas disponible';
    END IF;
    
    SELECT COUNT(*) INTO nb_emprunts 
    FROM Emprunt 
    WHERE IdAdherent = NEW.IdAdherent AND DateRetourEffective IS NULL;
    
    IF nb_emprunts >= 3 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Limite de 3 emprunts atteinte pour cet adhérent';
    END IF;
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `penalites_impayees_question_5`;
DELIMITER $$
CREATE TRIGGER `penalites_impayees_question_5` BEFORE INSERT ON `emprunt` FOR EACH ROW BEGIN
    DECLARE penalites_impayees INT;
    
    SELECT COUNT(*) INTO penalites_impayees
    FROM Penalite
    WHERE IdAdherent = NEW.IdAdherent AND Statut = 'En Attente';
    
    IF penalites_impayees > 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Adhérent a des pénalités impayées';
    END IF;
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `supprime_question_2`;
DELIMITER $$
CREATE TRIGGER `supprime_question_2` AFTER UPDATE ON `emprunt` FOR EACH ROW BEGIN
    IF NEW.DateRetourEffective IS NOT NULL AND OLD.DateRetourEffective IS NULL THEN
        UPDATE Exemplaire SET Statut = 'Disponible' WHERE IdExemplaire = NEW.IdExemplaire;
        UPDATE Livre l JOIN Exemplaire e ON l.ISBN = e.ISBN
        SET l.NombreExemplairesDisponibles = l.NombreExemplairesDisponibles + 1
        WHERE e.IdExemplaire = NEW.IdExemplaire;
    END IF;
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `unique_question_4`;
DELIMITER $$
CREATE TRIGGER `unique_question_4` BEFORE INSERT ON `emprunt` FOR EACH ROW BEGIN
    DECLARE nb_emprunts_meme_livre INT;
    
    SELECT COUNT(*) INTO nb_emprunts_meme_livre
    FROM Emprunt e
    JOIN Exemplaire ex ON e.IdExemplaire = ex.IdExemplaire
    JOIN Exemplaire new_ex ON ex.ISBN = new_ex.ISBN
    WHERE e.IdAdherent = NEW.IdAdherent 
    AND e.DateRetourEffective IS NULL
    AND new_ex.IdExemplaire = NEW.IdExemplaire;
    
    IF nb_emprunts_meme_livre > 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Adhérent a déjà un exemplaire de ce livre en cours d'emprunt';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `exemplaire`
--

DROP TABLE IF EXISTS `exemplaire`;
CREATE TABLE IF NOT EXISTS `exemplaire` (
  `IdExemplaire` int(11) NOT NULL AUTO_INCREMENT,
  `ISBN` varchar(13) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Statut` enum('Disponible','Emprunté','Réservé','Perdu') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Disponible',
  PRIMARY KEY (`IdExemplaire`),
  KEY `ISBN` (`ISBN`)
) ENGINE=InnoDB AUTO_INCREMENT=14 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `exemplaire`
--

INSERT INTO `exemplaire` (`IdExemplaire`, `ISBN`, `Statut`) VALUES
(1, '9782070360028', 'Disponible'),
(2, '9782070360028', 'Perdu'),
(3, '9782070360028', 'Disponible'),
(4, '9782070360530', 'Disponible'),
(5, '9782070360530', 'Disponible'),
(6, '9782290032726', 'Disponible'),
(7, '9782290032726', 'Disponible'),
(8, '9782070584621', 'Disponible'),
(9, '9782070584621', 'Disponible'),
(10, '9782070584621', 'Disponible'),
(11, '9782070584621', 'Disponible'),
(12, '9782253004247', 'Perdu'),
(13, '9782253004247', 'Disponible');

--
-- Déclencheurs `exemplaire`
--
DROP TRIGGER IF EXISTS `ajout_question_1`;
DELIMITER $$
CREATE TRIGGER `ajout_question_1` AFTER INSERT ON `exemplaire` FOR EACH ROW BEGIN
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal + 1,
        NombreExemplairesDisponibles = NombreExemplairesDisponibles + 1
    WHERE ISBN = NEW.ISBN;
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `supprime_question_1`;
DELIMITER $$
CREATE TRIGGER `supprime_question_1` AFTER DELETE ON `exemplaire` FOR EACH ROW BEGIN
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal - IF(OLD.Statut = 'Perdu', 0, 1),
        NombreExemplairesDisponibles = NombreExemplairesDisponibles - 
            CASE WHEN OLD.Statut = 'Disponible' THEN 1 ELSE 0 END
    WHERE ISBN = OLD.ISBN;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `livre`
--

DROP TABLE IF EXISTS `livre`;
CREATE TABLE IF NOT EXISTS `livre` (
  `ISBN` varchar(13) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Titre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `AnneeEdition` int(11) NOT NULL,
  `Editeur` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Genre` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL,
  `Valeur` decimal(10,2) NOT NULL,
  `DateAchat` date NOT NULL,
  `NombreExemplairesTotal` int(11) NOT NULL DEFAULT '0',
  `NombreExemplairesDisponibles` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`ISBN`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `livre`
--

INSERT INTO `livre` (`ISBN`, `Titre`, `AnneeEdition`, `Editeur`, `Genre`, `Valeur`, `DateAchat`, `NombreExemplairesTotal`, `NombreExemplairesDisponibles`) VALUES
('9782070360028', 'Les Misérables', 1862, 'Gallimard', 'Roman', '25.00', '2023-01-15', 2, 2),
('9782070360530', '1984', 1949, 'Gallimard', 'Science-Fiction', '20.00', '2023-02-20', 2, 2),
('9782070584621', 'Harry Potter à l\'école des sorciers', 1997, 'Gallimard', 'Fantasy', '22.00', '2023-04-05', 4, 4),
('9782253004247', 'Le Crime de l\'Orient-Express', 1934, 'Le Livre de Poche', 'Policier', '15.00', '2023-05-12', 1, 1),
('9782290032726', 'Fondation', 1951, 'J\'ai lu', 'Science-Fiction', '18.00', '2023-03-10', 2, 2);

-- --------------------------------------------------------

--
-- Structure de la table `livreauteur`
--

DROP TABLE IF EXISTS `livreauteur`;
CREATE TABLE IF NOT EXISTS `livreauteur` (
  `ISBN` varchar(13) COLLATE utf8mb4_unicode_ci NOT NULL,
  `IdAuteur` int(11) NOT NULL,
  PRIMARY KEY (`ISBN`,`IdAuteur`),
  KEY `IdAuteur` (`IdAuteur`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `livreauteur`
--

INSERT INTO `livreauteur` (`ISBN`, `IdAuteur`) VALUES
('9782070360028', 1),
('9782070360530', 2),
('9782290032726', 3),
('9782070584621', 4),
('9782253004247', 5);

-- --------------------------------------------------------

--
-- Structure de la table `penalite`
--

DROP TABLE IF EXISTS `penalite`;
CREATE TABLE IF NOT EXISTS `penalite` (
  `IdPenalite` int(11) NOT NULL AUTO_INCREMENT,
  `IdAdherent` int(11) NOT NULL,
  `IdEmprunt` int(11) NOT NULL,
  `Montant` decimal(10,2) NOT NULL,
  `DatePenalite` date NOT NULL,
  `Statut` enum('En Attente','Payée') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'En Attente',
  PRIMARY KEY (`IdPenalite`),
  KEY `IdAdherent` (`IdAdherent`),
  KEY `IdEmprunt` (`IdEmprunt`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `penalite`
--

INSERT INTO `penalite` (`IdPenalite`, `IdAdherent`, `IdEmprunt`, `Montant`, `DatePenalite`, `Statut`) VALUES
(1, 1, 1, '1000.00', CURDATE(), 'En Attente'),
(2, 1, 2, '1000.00', CURDATE(), 'En Attente'),
(3, 2, 6, '25.00', CURDATE(), 'En Attente'),
(4, 3, 7, '15.00', CURDATE(), 'En Attente');

-- --------------------------------------------------------

--
-- Structure de la table `reservation`
--

DROP TABLE IF EXISTS `reservation`;
CREATE TABLE IF NOT EXISTS `reservation` (
  `IdReservation` int(11) NOT NULL AUTO_INCREMENT,
  `IdAdherent` int(11) NOT NULL,
  `ISBN` varchar(13) COLLATE utf8mb4_unicode_ci NOT NULL,
  `DateReservation` date NOT NULL,
  `DateLimiteRecuperation` date NOT NULL,
  `Statut` enum('En Attente','Notifiée','Expirée','Terminée') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'En Attente',
  PRIMARY KEY (`IdReservation`),
  KEY `IdAdherent` (`IdAdherent`),
  KEY `ISBN` (`ISBN`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `reservation`
--

INSERT INTO `reservation` (`IdReservation`, `IdAdherent`, `ISBN`, `DateReservation`, `DateLimiteRecuperation`, `Statut`) VALUES
(2, 2, '9782070360028', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'Notifiée'),
(3, 3, '9782070584621', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente'),
(4, 4, '9782253004247', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente'),
(5, 5, '9782070360530', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente'),
(6, 1, '9782290032726', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'En Attente');

-- Déclencheur de validation des réservations
DELIMITER $$
CREATE TRIGGER `verifier_reservation` BEFORE INSERT ON `reservation` FOR EACH ROW BEGIN
    DECLARE abonnement_actif INT;
    DECLARE exemplaires_existants INT;
    DECLARE nb_emprunts INT;
    DECLARE nb_reservations INT;
    DECLARE limite_reservations INT;

    SELECT COUNT(*) INTO abonnement_actif
    FROM Abonnement
    WHERE IdAdherent = NEW.IdAdherent
      AND Statut = 'Actif'
      AND CURDATE() BETWEEN DateDebut AND DateFin;

    IF abonnement_actif = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Un abonnement actif est requis pour réserver';
    END IF;

    SELECT COUNT(*) INTO exemplaires_existants
    FROM Exemplaire
    WHERE ISBN = NEW.ISBN AND Statut <> 'Perdu';

    IF exemplaires_existants = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ce livre ne possède aucun exemplaire';
    END IF;

    SELECT COUNT(*) INTO nb_emprunts
    FROM Emprunt
    WHERE IdAdherent = NEW.IdAdherent AND DateRetourEffective IS NULL;

    SELECT COUNT(*) INTO nb_reservations
    FROM Reservation
    WHERE IdAdherent = NEW.IdAdherent
      AND Statut IN ('En Attente', 'Notifiée');

    SET limite_reservations = IF(nb_emprunts >= 3, 1, 2);
    IF nb_reservations >= limite_reservations THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Limite de réservations atteinte pour cet adhérent';
    END IF;
END$$
DELIMITER ;

--
-- Contraintes pour les tables déchargées
--

--
-- Contraintes pour la table `abonnement`
--
ALTER TABLE `abonnement`
  ADD CONSTRAINT `abonnement_ibfk_1` FOREIGN KEY (`IdAdherent`) REFERENCES `adherent` (`IdAdherent`) ON DELETE CASCADE;

--
-- Contraintes pour la table `emprunt`
--
ALTER TABLE `emprunt`
  ADD CONSTRAINT `emprunt_ibfk_1` FOREIGN KEY (`IdAdherent`) REFERENCES `adherent` (`IdAdherent`),
  ADD CONSTRAINT `emprunt_ibfk_2` FOREIGN KEY (`IdExemplaire`) REFERENCES `exemplaire` (`IdExemplaire`);

--
-- Contraintes pour la table `exemplaire`
--
ALTER TABLE `exemplaire`
  ADD CONSTRAINT `exemplaire_ibfk_1` FOREIGN KEY (`ISBN`) REFERENCES `livre` (`ISBN`) ON DELETE CASCADE;

--
-- Contraintes pour la table `livreauteur`
--
ALTER TABLE `livreauteur`
  ADD CONSTRAINT `livreauteur_ibfk_1` FOREIGN KEY (`ISBN`) REFERENCES `livre` (`ISBN`) ON DELETE CASCADE,
  ADD CONSTRAINT `livreauteur_ibfk_2` FOREIGN KEY (`IdAuteur`) REFERENCES `auteur` (`IdAuteur`) ON DELETE CASCADE;

--
-- Contraintes pour la table `penalite`
--
ALTER TABLE `penalite`
  ADD CONSTRAINT `penalite_ibfk_1` FOREIGN KEY (`IdAdherent`) REFERENCES `adherent` (`IdAdherent`),
  ADD CONSTRAINT `penalite_ibfk_2` FOREIGN KEY (`IdEmprunt`) REFERENCES `emprunt` (`IdEmprunt`);

--
-- Contraintes pour la table `reservation`
--
ALTER TABLE `reservation`
  ADD CONSTRAINT `reservation_ibfk_1` FOREIGN KEY (`IdAdherent`) REFERENCES `adherent` (`IdAdherent`),
  ADD CONSTRAINT `reservation_ibfk_2` FOREIGN KEY (`ISBN`) REFERENCES `livre` (`ISBN`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
