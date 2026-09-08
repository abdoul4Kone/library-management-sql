-- phpMyAdmin SQL Dump
-- version 4.9.2
-- https://www.phpmyadmin.net/
--
-- Hôte : 127.0.0.1:3308
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
CREATE DEFINER=`root`@`localhost` PROCEDURE `enregistrer_retour` (IN `p_id_emprunt` INT, IN `p_date_retour` DATE)  BEGIN
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
CREATE DEFINER=`root`@`localhost` PROCEDURE `supprimer_exemplaire_egare` (IN `p_id_exemplaire` INT, IN `p_id_adherent` INT)  BEGIN
    DECLARE v_isbn VARCHAR(13);
    DECLARE v_valeur DECIMAL(10,2);
    DECLARE v_id_emprunt INT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Trouver l'emprunt actif pour cet exemplaire (s'il existe)
    SELECT IdEmprunt INTO v_id_emprunt
    FROM Emprunt
    WHERE IdExemplaire = p_id_exemplaire AND DateRetourEffective IS NULL
    LIMIT 1;
    
    -- Récupérer l'ISBN et la valeur du livre
    SELECT e.ISBN, l.Valeur INTO v_isbn, v_valeur
    FROM Exemplaire e
    JOIN Livre l ON e.ISBN = l.ISBN
    WHERE e.IdExemplaire = p_id_exemplaire;
    
    -- Enregistrer la pénalité (avec IdEmprunt si trouvé)
    INSERT INTO Penalite (IdAdherent, IdEmprunt, Montant, DatePenalite, Statut)
    VALUES (p_id_adherent, v_id_emprunt, v_valeur, CURDATE(), 'En Attente');
    
    -- Supprimer l'exemplaire
    DELETE FROM Exemplaire WHERE IdExemplaire = p_id_exemplaire;
    
    -- Mettre à jour le statut du livre
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal - 1,
        NombreExemplairesDisponibles = NombreExemplairesDisponibles - 
            CASE WHEN (SELECT Statut FROM Exemplaire WHERE IdExemplaire = p_id_exemplaire) = 'Disponible' 
                 THEN 1 ELSE 0 END
    WHERE ISBN = v_isbn;
    
    COMMIT;
END$$

DROP PROCEDURE IF EXISTS `traiter_reservations_expirees`$$
CREATE DEFINER=`root`@`localhost` PROCEDURE `traiter_reservations_expirees` ()  BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_isbn VARCHAR(13);
    DECLARE cur CURSOR FOR 
        SELECT DISTINCT ISBN FROM Reservation 
        WHERE Statut = 'Expirée' AND DateLimiteRecuperation < CURDATE();
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Supprimer les réservations expirées
    DELETE FROM Reservation 
    WHERE Statut = 'Expirée' AND DateLimiteRecuperation < CURDATE();
    
    -- Pour chaque livre concerné, notifier la prochaine réservation
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_isbn;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Notifier la prochaine réservation en attente
        UPDATE Reservation
        SET Statut = 'Notifiée',
            DateLimiteRecuperation = DATE_ADD(CURDATE(), INTERVAL 3 DAY)
        WHERE ISBN = v_isbn
        AND Statut = 'En Attente'
        AND IdReservation = (
            SELECT MIN(r.IdReservation)
            FROM Reservation r
            WHERE r.ISBN = v_isbn
            AND r.Statut = 'En Attente'
        );
    END LOOP;
    CLOSE cur;
    
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
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `abonnement`
--

INSERT INTO `abonnement` (`IdAbonnement`, `IdAdherent`, `DateDebut`, `DateFin`, `Montant`, `Statut`) VALUES
(1, 1, '2023-01-01', '2023-12-31', '5000.00', 'Actif'),
(2, 2, '2023-02-01', '2023-11-30', '5000.00', 'Actif'),
(3, 3, '2023-03-01', '2023-10-31', '5000.00', 'Actif'),
(4, 5, '2023-05-01', '2023-09-30', '5000.00', 'Actif');

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
(1, 'Dupont', 'Jean', '1 rue de Paris', '0612345678', '2023-01-10', 1),
(2, 'Martin', 'Sophie', '5 avenue des Champs', '0623456789', '2023-02-15', 1),
(3, 'Bernard', 'Pierre', '10 rue de Lyon', '0634567890', '2023-03-20', 1),
(4, 'Petit', 'Marie', '15 boulevard Voltaire', '0645678901', '2023-04-25', 0),
(5, 'Durand', 'Luc', '20 avenue Foch', '0656789012', '2023-05-30', 1);

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
) ENGINE=InnoDB AUTO_INCREMENT=21 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `auteur`
--

INSERT INTO `auteur` (`IdAuteur`, `Nom`, `Prenom`, `Nationalite`) VALUES
(1, 'Hugo', 'Victor', 'Française'),
(2, 'Orwell', 'George', 'Britannique'),
(3, 'Asimov', 'Isaac', 'Américaine'),
(4, 'Rowling', 'J.K.', 'Britannique'),
(5, 'Christie', 'Agatha', 'Britannique'),
(6, 'Hugo', 'Victor', 'Française'),
(7, 'Orwell', 'George', 'Britannique'),
(8, 'Asimov', 'Isaac', 'Américaine'),
(9, 'Rowling', 'J.K.', 'Britannique'),
(10, 'Christie', 'Agatha', 'Britannique'),
(11, 'Hugo', 'Victor', 'Française'),
(12, 'Orwell', 'George', 'Britannique'),
(13, 'Asimov', 'Isaac', 'Américaine'),
(14, 'Rowling', 'J.K.', 'Britannique'),
(15, 'Christie', 'Agatha', 'Britannique'),
(16, 'Hugo', 'Victor', 'Française'),
(17, 'Orwell', 'George', 'Britannique'),
(18, 'Asimov', 'Isaac', 'Américaine'),
(19, 'Rowling', 'J.K.', 'Britannique'),
(20, 'Christie', 'Agatha', 'Britannique');

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
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `emprunt`
--

INSERT INTO `emprunt` (`IdEmprunt`, `IdAdherent`, `IdExemplaire`, `DateDebut`, `DateRetourPrevue`, `DateRetourEffective`, `Penalite`) VALUES
(1, 1, 1, '2023-06-01', '2023-06-16', '2023-06-18', '1000.00'),
(2, 1, 4, '2023-06-05', '2023-06-20', '2023-06-27', '3500.00'),
(3, 2, 6, '2023-06-10', '2023-06-25', NULL, '0.00'),
(4, 3, 8, '2023-06-15', '2023-06-30', NULL, '0.00'),
(5, 5, 11, '2023-06-20', '2023-07-05', NULL, '0.00');

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
(2, '9782070360028', 'Disponible'),
(3, '9782070360028', 'Disponible'),
(4, '9782070360530', 'Disponible'),
(5, '9782070360530', 'Disponible'),
(6, '9782290032726', 'Emprunté'),
(7, '9782290032726', 'Disponible'),
(8, '9782070584621', 'Emprunté'),
(9, '9782070584621', 'Disponible'),
(10, '9782070584621', 'Disponible'),
(11, '9782070584621', 'Emprunté'),
(12, '9782253004247', 'Disponible'),
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
    SET NombreExemplairesTotal = NombreExemplairesTotal - 1,
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
('9782070360028', 'Les Misérables', 1862, 'Gallimard', 'Roman', '25.00', '2023-01-15', 6, 6),
('9782070360530', '1984', 1949, 'Gallimard', 'Science-Fiction', '20.00', '2023-02-20', 4, 4),
('9782070584621', 'Harry Potter à l\'école des sorciers', 1997, 'Gallimard', 'Fantasy', '22.00', '2023-04-05', 8, 6),
('9782253004247', 'Le Crime de l\'Orient-Express', 1934, 'Le Livre de Poche', 'Policier', '15.00', '2023-05-12', 4, 4),
('9782290032726', 'Fondation', 1951, 'J\'ai lu', 'Science-Fiction', '18.00', '2023-03-10', 4, 3);

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
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `penalite`
--

INSERT INTO `penalite` (`IdPenalite`, `IdAdherent`, `IdEmprunt`, `Montant`, `DatePenalite`, `Statut`) VALUES
(1, 1, 1, '1000.00', '2025-04-06', 'En Attente'),
(2, 1, 2, '3500.00', '2025-04-06', 'En Attente'),
(3, 1, 1, '1000.00', '2025-04-06', 'En Attente'),
(4, 1, 2, '3500.00', '2025-04-06', 'En Attente'),
(5, 1, 1, '1000.00', '2025-04-06', 'En Attente'),
(6, 1, 2, '3500.00', '2025-04-06', 'En Attente'),
(7, 1, 1, '1000.00', '2025-04-06', 'En Attente'),
(8, 1, 2, '3500.00', '2025-04-06', 'En Attente');

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
  `Statut` enum('En Attente','Expirée','Terminée') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'En Attente',
  PRIMARY KEY (`IdReservation`),
  KEY `IdAdherent` (`IdAdherent`),
  KEY `ISBN` (`ISBN`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Déchargement des données de la table `reservation`
--

INSERT INTO `reservation` (`IdReservation`, `IdAdherent`, `ISBN`, `DateReservation`, `DateLimiteRecuperation`, `Statut`) VALUES
(1, 4, '9782070360028', '2023-06-25', '2023-06-28', 'En Attente'),
(2, 2, '9782290032726', '2023-06-26', '2023-06-29', 'En Attente'),
(3, 3, '9782070584621', '2023-06-27', '2023-06-30', 'En Attente');

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
