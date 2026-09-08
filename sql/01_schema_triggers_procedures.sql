-- On crée la base de données avec un encodage qui supporte les caractères spéciaux
CREATE DATABASE IF NOT EXISTS BiblioTecho CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- On se positionne sur la base qu'on vient de créer
USE BiblioTecho;

-- ****************************************************************************
-- ************************************TABLES**********************************
-- ****************************************************************************
-- table qui stocke les informations sur les auteurs des livres
-- un auteur peut avoir écrit plusieurs livres, et un livre peut avoir plusieurs auteurs
CREATE TABLE Auteur (
    IdAuteur INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique auto-généré
    Nom VARCHAR(50) NOT NULL,                -- Le nom de famille de l'auteur
    Prenom VARCHAR(50) NOT NULL,             -- Le prénom de l'auteur
    Nationalite VARCHAR(50) NOT NULL         -- La nationalité, utile pour les statistiques
) ENGINE=InnoDB;  -- On utilise InnoDB pour ses fonctionnalités transactionnelles

-- ****************************************************************************
-- table qui représente les livres dans notre catalogue
-- un livre peut avoir plusieurs exemplaires physiques (voir table Exemplaire)
CREATE TABLE Livre (
    ISBN VARCHAR(13) PRIMARY KEY,            -- Le code ISBN international, idéal comme clé primaire
    Titre VARCHAR(100) NOT NULL,             -- Le titre du livre (évidemment obligatoire!)
    AnneeEdition INT NOT NULL,               -- L'année d'édition pour savoir si c'est récent
    Editeur VARCHAR(50) NOT NULL,            -- La maison d'édition
    Genre VARCHAR(30) NOT NULL,              -- Le genre littéraire (roman, science, etc.)
    Valeur DECIMAL(10,2) NOT NULL,           -- Valeur monétaire du livre (pour les pénalités)
    DateAchat DATE NOT NULL,                 -- Quand on l'a acheté (pour calculer la dépréciation)
    NombreExemplairesTotal INT DEFAULT 0 NOT NULL,      -- Nb total d'exemplaires de ce livre
    NombreExemplairesDisponibles INT DEFAULT 0 NOT NULL -- Nb d'exemplaires disponibles
) ENGINE=InnoDB;

-- ****************************************************************************
-- cette table fait le lien entre les livres et les auteurs
CREATE TABLE LivreAuteur (
    ISBN VARCHAR(13) NOT NULL,       -- Référence au livre
    IdAuteur INT NOT NULL,           -- Référence à l'auteur
    PRIMARY KEY (ISBN, IdAuteur),    -- Clé primaire composée
    
    -- Si on supprime un livre, on supprime automatiquement ses liens avec les auteurs
    FOREIGN KEY (ISBN) REFERENCES Livre(ISBN) ON DELETE CASCADE,
    
    -- Si on supprime un auteur, on supprime automatiquement ses liens avec les livres
    FOREIGN KEY (IdAuteur) REFERENCES Auteur(IdAuteur) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ****************************************************************************
-- table pour les exemplaires physiques des livres
-- un même livre (ISBN) peut avoir plusieurs exemplaires (avec des codes différents)
CREATE TABLE Exemplaire (
    IdExemplaire INT AUTO_INCREMENT PRIMARY KEY,  -- Code unique pour chaque exemplaire
    ISBN VARCHAR(13) NOT NULL,                   -- Référence au livre correspondant
    Statut ENUM('Disponible', 'Emprunté', 'Réservé', 'Perdu') DEFAULT 'Disponible' NOT NULL,
    
    -- Si on supprime un livre, on supprime automatiquement tous ses exemplaires
    FOREIGN KEY (ISBN) REFERENCES Livre(ISBN) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ****************************************************************************
-- table qui contient les informations sur les membres de la bibliothèque
CREATE TABLE Adherent (
    IdAdherent INT AUTO_INCREMENT PRIMARY KEY,  -- Numéro unique d'adhérent
    Nom VARCHAR(50) NOT NULL,                  -- Nom de famille
    Prenom VARCHAR(50) NOT NULL,               -- Prénom
    Adresse VARCHAR(100) NOT NULL,             -- Adresse postale (pour les relances)
    Telephone VARCHAR(20) NOT NULL,            -- Numéro de téléphone (important!)
    DateInscription DATE NOT NULL,             -- Quand il/elle a rejoint la bibliothèque
    AbonnementActif BOOLEAN DEFAULT FALSE NOT NULL  -- Est-ce que son abonnement est valide?
) ENGINE=InnoDB;

-- ****************************************************************************
-- gestion des abonnements des adhérents
-- un adhérent peut avoir plusieurs abonnements successifs dans le temps
CREATE TABLE Abonnement (
    IdAbonnement INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique de l'abonnement
    IdAdherent INT NOT NULL,                     -- Référence à l'adhérent
    DateDebut DATE NOT NULL,                     -- Date de début de validité
    DateFin DATE NOT NULL,                       -- Date de fin de validité
    Montant DECIMAL(10,2) DEFAULT 5000.00 NOT NULL,  -- Montant (5000 FCFA par défaut)
    Statut ENUM('Actif', 'Expiré') DEFAULT 'Actif' NOT NULL,  -- Est-il encore valable?
    
    -- Si on supprime un adhérent, on supprime automatiquement ses abonnements
    FOREIGN KEY (IdAdherent) REFERENCES Adherent(IdAdherent) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ****************************************************************************
-- cette table enregistre tous les emprunts de livres par les adhérents
CREATE TABLE Emprunt (
    IdEmprunt INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique de l'emprunt
    IdAdherent INT NOT NULL,                   -- Qui a emprunté?
    IdExemplaire INT NOT NULL,                 -- Quel exemplaire précisément?
    DateDebut DATE NOT NULL,                   -- Date du début de l'emprunt
    DateRetourPrevue DATE NOT NULL,            -- Date à laquelle il devrait être rendu
    DateRetourEffective DATE,                  -- Date réelle de retour (NULL si pas encore rendu)
    Penalite DECIMAL(10,2) DEFAULT 0.00,       -- Montant de la pénalité si retard
    
    -- Contrôle d'intégrité référentielle
    FOREIGN KEY (IdAdherent) REFERENCES Adherent(IdAdherent),
    FOREIGN KEY (IdExemplaire) REFERENCES Exemplaire(IdExemplaire)
) ENGINE=InnoDB;

-- ****************************************************************************
-- table qui gère les réservations de livres 
CREATE TABLE Reservation (
    IdReservation INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique
    IdAdherent INT NOT NULL,                      -- Qui réserve?
    ISBN VARCHAR(13) NOT NULL,                    -- Quel livre (pas d'exemplaire spécifique)
    DateReservation DATE NOT NULL,                -- Quand la réservation a été faite
    DateLimiteRecuperation DATE NOT NULL,         -- Date limite pour venir chercher le livre
    Statut ENUM('En Attente', 'Expirée', 'Terminée') DEFAULT 'En Attente' NOT NULL,
    
    -- Contrôle d'intégrité référentielle
    FOREIGN KEY (IdAdherent) REFERENCES Adherent(IdAdherent),
    FOREIGN KEY (ISBN) REFERENCES Livre(ISBN)
) ENGINE=InnoDB;

-- ****************************************************************************
-- Cette table enregistre les pénalités pour retard ou livre perdu
CREATE TABLE Penalite (
    IdPenalite INT AUTO_INCREMENT PRIMARY KEY,  -- Identifiant unique
    IdAdherent INT NOT NULL,                    -- Qui doit payer?
    IdEmprunt INT NOT NULL,                     -- Pour quel emprunt?
    Montant DECIMAL(10,2) NOT NULL,             -- Combien doit-il?
    DatePenalite DATE NOT NULL,                 -- Date de la pénalité
    Statut ENUM('En Attente', 'Payée') DEFAULT 'En Attente' NOT NULL,  -- Est-ce payé?
    
    -- Contrôle d'intégrité référentielle
    FOREIGN KEY (IdAdherent) REFERENCES Adherent(IdAdherent),
    FOREIGN KEY (IdEmprunt) REFERENCES Emprunt(IdEmprunt)
) ENGINE=InnoDB;

-- ****************************************************************************
-- ***********************************QUESTIONS******************************
-- ****************************************************************************

-- ****************************************************************************
-- QUESTION 1 : Triggers pour mise à jour du nombre d'exemplaires
-- "Mettre en place un trigger qui met à jour le nombre total de livre à chaque 
-- ajout ou suppression d'un exemplaire."
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER ajout_question_1
AFTER INSERT ON Exemplaire
FOR EACH ROW
BEGIN
    /* Ce trigger s'active après chaque ajout d'un nouvel exemplaire
       et met à jour les compteurs dans la table Livre */
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal + 1,
        NombreExemplairesDisponibles = NombreExemplairesDisponibles + 1
    WHERE ISBN = NEW.ISBN;
END //

CREATE TRIGGER supprime_question_1
AFTER DELETE ON Exemplaire
FOR EACH ROW
BEGIN
    /* Ce trigger s'active après suppression d'un exemplaire
       et ajuste les compteurs en fonction du statut de l'exemplaire supprimé */
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal - 1,
        NombreExemplairesDisponibles = NombreExemplairesDisponibles - 
            CASE WHEN OLD.Statut = 'Disponible' THEN 1 ELSE 0 END
    WHERE ISBN = OLD.ISBN;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 2 : Triggers pour gestion des disponibilités
-- "Mettre en place un trigger qui met à jour le nombre d'exemplaires 
-- disponibles à chaque emprunt et retour"
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER ajout_question_2
AFTER INSERT ON Emprunt
FOR EACH ROW
BEGIN
    /* Lors d'un nouvel emprunt :
       1. Met à jour le statut de l'exemplaire à "Emprunté"
       2. Décrémente le compteur d'exemplaires disponibles */
    UPDATE Exemplaire SET Statut = 'Emprunté' WHERE IdExemplaire = NEW.IdExemplaire;
    UPDATE Livre l JOIN Exemplaire e ON l.ISBN = e.ISBN
    SET l.NombreExemplairesDisponibles = l.NombreExemplairesDisponibles - 1
    WHERE e.IdExemplaire = NEW.IdExemplaire;
END //

CREATE TRIGGER supprime_question_2
AFTER UPDATE ON Emprunt
FOR EACH ROW
BEGIN
    /* Lors du retour d'un livre (date effective renseignée) :
       1. Remet le statut à "Disponible"
       2. Incrémente le compteur d'exemplaires disponibles */
    IF NEW.DateRetourEffective IS NOT NULL AND OLD.DateRetourEffective IS NULL THEN
        UPDATE Exemplaire SET Statut = 'Disponible' WHERE IdExemplaire = NEW.IdExemplaire;
        UPDATE Livre l JOIN Exemplaire e ON l.ISBN = e.ISBN
        SET l.NombreExemplairesDisponibles = l.NombreExemplairesDisponibles + 1
        WHERE e.IdExemplaire = NEW.IdExemplaire;
    END IF;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 3 : Trigger pour limite d'emprunts
-- "Mettre en place un trigger qui vérifie que le nombre de livre emprunté par 
-- un adhérent n'excède pas 3 avant la validation de l'emprunt."
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER limite_emprunts_question_3
BEFORE INSERT ON Emprunt
FOR EACH ROW
BEGIN
    /* Empêche un adhérent d'avoir plus de 3 emprunts simultanés */
    DECLARE nb_emprunts INT;
    
    SELECT COUNT(*) INTO nb_emprunts 
    FROM Emprunt 
    WHERE IdAdherent = NEW.IdAdherent AND DateRetourEffective IS NULL;
    
    IF nb_emprunts >= 3 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Limite de 3 emprunts atteinte pour cet adhérent';
    END IF;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 4 : Trigger pour exemplaire unique
-- "Mettre en place un trigger qui vérifie qu'un adhérent n'est pas en train 
-- d'emprunter plus d'un exemplaire d'un livre donné avant validation de l'emprunt."
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER unique_question_4
BEFORE INSERT ON Emprunt
FOR EACH ROW
BEGIN
    /* Empêche un adhérent d'emprunter plusieurs exemplaires du même livre */
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
        SET MESSAGE_TEXT = 'Adhérent a déjà un exemplaire de ce livre en cours d''emprunt';
    END IF;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 5 : Trigger pour pénalités impayées
-- "Mettre en place un trigger qui vérifie qu'un adhérent n'a pas de pénalités 
-- non payées avant validation d'un emprunt."
-- ****************************************************************************

DELIMITER //
CREATE TRIGGER penalites_impayees_question_5
BEFORE INSERT ON Emprunt
FOR EACH ROW
BEGIN
    /* Bloque l'emprunt si l'adhérent a des pénalités non réglées */
    DECLARE penalites_impayees INT;
    
    SELECT COUNT(*) INTO penalites_impayees
    FROM Penalite
    WHERE IdAdherent = NEW.IdAdherent AND Statut = 'En Attente';
    
    IF penalites_impayees > 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Adhérent a des pénalités impayées';
    END IF;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 6 : Transaction pour exemplaire égaré
-- "Mettre en place une transaction permettant de supprimer un exemplaire
-- égaré par un adhérent."
-- ****************************************************************************

DELIMITER //
CREATE PROCEDURE supprimer_exemplaire_egare(
    IN p_id_exemplaire INT,
    IN p_id_adherent INT
)
BEGIN
    /* Procédure transactionnelle pour :
       1. Enregistrer une pénalité pour l'adhérent
       2. Supprimer l'exemplaire perdu
       3. Mettre à jour les compteurs */
    DECLARE v_isbn VARCHAR(13);
    DECLARE v_valeur DECIMAL(10,2);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Récupérer l'ISBN et la valeur du livre
    SELECT e.ISBN, l.Valeur INTO v_isbn, v_valeur
    FROM Exemplaire e
    JOIN Livre l ON e.ISBN = l.ISBN
    WHERE e.IdExemplaire = p_id_exemplaire;
    
    -- Enregistrer la pénalité (valeur du livre)
    INSERT INTO Penalite (IdAdherent, IdEmprunt, Montant, DatePenalite, Statut)
    VALUES (p_id_adherent, NULL, v_valeur, CURDATE(), 'En Attente');
    
    -- Supprimer l'exemplaire
    DELETE FROM Exemplaire WHERE IdExemplaire = p_id_exemplaire;
    
    -- Mettre à jour les compteurs du livre
    UPDATE Livre 
    SET NombreExemplairesTotal = NombreExemplairesTotal - 1,
        NombreExemplairesDisponibles = NombreExemplairesDisponibles - 
            CASE WHEN (SELECT Statut FROM Exemplaire WHERE IdExemplaire = p_id_exemplaire) = 'Disponible' 
                 THEN 1 ELSE 0 END
    WHERE ISBN = v_isbn;
    
    COMMIT;
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 7 : Transaction pour retour de livre
-- "Ecrire une transaction pour enregistrer les retours de livre. Cette
-- transaction évalue s'il y a des pénalités à appliquées et les enregistres."
-- ****************************************************************************

DELIMITER //
CREATE PROCEDURE enregistrer_retour(
    IN p_id_emprunt INT,
    IN p_date_retour DATE
)
BEGIN
    /* Procédure transactionnelle pour :
       1. Enregistrer la date de retour effective
       2. Calculer les pénalités si retard
       3. Mettre à jour les données */
    DECLARE v_retard INT;
    DECLARE v_id_adherent INT;
    DECLARE v_penalite DECIMAL(10,2);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- Calculer le retard en jours (500 FCFA par jour)
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
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 8 : Paiement de pénalité
-- "Ecrire une requête SQL permettant d'enregistrer le paiement d'une pénalité."
-- ****************************************************************************

UPDATE Penalite
SET Statut = 'Payée',
    DatePenalite = CURDATE()
WHERE IdPenalite = [id_penalite]; -- À remplacer par l'ID réel

-- ****************************************************************************
-- QUESTION 9 : Désactivation abonnements expirés
-- "Ecrire une requête SQL permettant de désactiver tous les abonnements
-- arrivés à expiration."
-- ****************************************************************************

-- Désactive les abonnements expirés
UPDATE Abonnement
SET Statut = 'Expiré'
WHERE DateFin < CURDATE() AND Statut = 'Actif';

-- Met à jour le statut des adhérents concernés
UPDATE Adherent a
JOIN Abonnement ab ON a.IdAdherent = ab.IdAdherent
SET a.AbonnementActif = FALSE
WHERE ab.DateFin < CURDATE() AND ab.Statut = 'Expiré';

-- ****************************************************************************
-- QUESTION 10 : Mise à jour réservations
-- "Ecrire une requête SQL permettant de mettre à jour les réservations."
-- ****************************************************************************

-- Marque les réservations expirées (non récupérées dans les 3 jours)
UPDATE Reservation
SET Statut = 'Expirée'
WHERE DateLimiteRecuperation < CURDATE() AND Statut = 'En Attente';

-- Notifie la prochaine réservation en attente quand un exemplaire est disponible
UPDATE Reservation r
JOIN Livre l ON r.ISBN = l.ISBN
SET r.Statut = 'Notifiée'
WHERE l.NombreExemplairesDisponibles > 0 
AND r.Statut = 'En Attente'
AND r.IdReservation = (
    SELECT MIN(r2.IdReservation)
    FROM Reservation r2
    WHERE r2.ISBN = r.ISBN
    AND r2.Statut = 'En Attente'
);

-- ****************************************************************************
-- QUESTION 11 : Transaction pour réservations expirées
-- "Ecrire une transaction qui supprime toutes les réservations arrivées à
-- expiration (3 jours sans réaction de l'adhérent) puis met à jour les
-- réservations en attente par ordre de priorité en fonction des disponibilités."
-- ****************************************************************************

DELIMITER //
CREATE PROCEDURE traiter_reservations_expirees()
BEGIN
    /* Procédure transactionnelle pour :
       1. Supprimer les réservations expirées
       2. Notifier les suivants dans la file d'attente */
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
    
    -- Pour chaque livre concerné, notifier la prochaine réservation en attente
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_isbn;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
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
END //
DELIMITER ;

-- ****************************************************************************
-- QUESTION 12 : Enregistrement d'occurences
-- " Enregistrer au moins 5 occurrences de livres, d’emprunts, de réservations, 
--  de retours de livre, de suppression de livres avec 2 livres égarés par des 
--  adhérents pour vérifier la bonne marche de votre base de données
-- ****************************************************************************

-- Insertion d'auteurs
INSERT INTO Auteur (Nom, Prenom, Nationalite) VALUES
('Hugo', 'Victor', 'Française'),
('Orwell', 'George', 'Britannique'),
('Asimov', 'Isaac', 'Américaine'),
('Rowling', 'J.K.', 'Britannique'),
('Christie', 'Agatha', 'Britannique');

-- Insertion de livres
INSERT INTO Livre (ISBN, Titre, AnneeEdition, Editeur, Genre, Valeur, DateAchat, NombreExemplairesTotal, NombreExemplairesDisponibles) VALUES
('9782070360028', 'Les Misérables', 1862, 'Gallimard', 'Roman', 25.00, '2023-01-15', 3, 3),
('9782070360530', '1984', 1949, 'Gallimard', 'Science-Fiction', 20.00, '2023-02-20', 2, 2),
('9782290032726', 'Fondation', 1951, 'J''ai lu', 'Science-Fiction', 18.00, '2023-03-10', 2, 2),
('9782070584621', 'Harry Potter à l''école des sorciers', 1997, 'Gallimard', 'Fantasy', 22.00, '2023-04-05', 4, 4),
('9782253004247', 'Le Crime de l''Orient-Express', 1934, 'Le Livre de Poche', 'Policier', 15.00, '2023-05-12', 2, 2);

-- Insertion de relations Livre-Auteur
INSERT INTO LivreAuteur (ISBN, IdAuteur) VALUES
('9782070360028', 1),
('9782070360530', 2),
('9782290032726', 3),
('9782070584621', 4),
('9782253004247', 5);

-- Insertion d'exemplaires
INSERT INTO Exemplaire (ISBN, Statut) VALUES
('9782070360028', 'Disponible'),
('9782070360028', 'Disponible'),
('9782070360028', 'Disponible'),
('9782070360530', 'Disponible'),
('9782070360530', 'Disponible'),
('9782290032726', 'Disponible'),
('9782290032726', 'Disponible'),
('9782070584621', 'Disponible'),
('9782070584621', 'Disponible'),
('9782070584621', 'Disponible'),
('9782070584621', 'Disponible'),
('9782253004247', 'Disponible'),
('9782253004247', 'Disponible');

-- Insertion d'adhérents
INSERT INTO Adherent (Nom, Prenom, Adresse, Telephone, DateInscription, AbonnementActif) VALUES
('Dupont', 'Jean', '1 rue de Paris', '0612345678', '2023-01-10', TRUE),
('Martin', 'Sophie', '5 avenue des Champs', '0623456789', '2023-02-15', TRUE),
('Bernard', 'Pierre', '10 rue de Lyon', '0634567890', '2023-03-20', TRUE),
('Petit', 'Marie', '15 boulevard Voltaire', '0645678901', '2023-04-25', FALSE),
('Durand', 'Luc', '20 avenue Foch', '0656789012', '2023-05-30', TRUE);

-- Insertion d'abonnements
INSERT INTO Abonnement (IdAdherent, DateDebut, DateFin, Montant, Statut) VALUES
(1, '2023-01-01', '2023-12-31', 5000.00, 'Actif'),
(2, '2023-02-01', '2023-11-30', 5000.00, 'Actif'),
(3, '2023-03-01', '2023-10-31', 5000.00, 'Actif'),
(5, '2023-05-01', '2023-09-30', 5000.00, 'Actif');

-- Insertion d'emprunts
INSERT INTO Emprunt (IdAdherent, IdExemplaire, DateDebut, DateRetourPrevue) VALUES
(1, 1, '2023-06-01', '2023-06-16'),
(1, 4, '2023-06-05', '2023-06-20'),
(2, 6, '2023-06-10', '2023-06-25'),
(3, 8, '2023-06-15', '2023-06-30'),
(5, 11, '2023-06-20', '2023-07-05');

-- Insertion de réservations
INSERT INTO Reservation (IdAdherent, ISBN, DateReservation, DateLimiteRecuperation, Statut) VALUES
(4, '9782070360028', '2023-06-25', '2023-06-28', 'En Attente'),
(2, '9782290032726', '2023-06-26', '2023-06-29', 'En Attente'),
(3, '9782070584621', '2023-06-27', '2023-06-30', 'En Attente');

-- Enregistrement de retours avec pénalités
CALL enregistrer_retour(1, '2023-06-18'); -- 2 jours de retard
CALL enregistrer_retour(2, '2023-06-27'); -- 2 jours de retard



-- ****************************************************************************
-- QUESTION 13 : Requête livres scientifiques par adhérent
-- "Ecrire une requête SQL permettant d'afficher tous les livres du genre
-- science commandés par chaque adhérent."
-- ****************************************************************************

SELECT 
    a.IdAdherent,
    CONCAT(a.Nom, ' ', a.Prenom) AS Adherent,
    l.Titre,
    l.Genre,
    COUNT(e.IdEmprunt) AS NombreEmprunts
FROM 
    Adherent a
JOIN 
    Emprunt e ON a.IdAdherent = e.IdAdherent
JOIN 
    Exemplaire ex ON e.IdExemplaire = ex.IdExemplaire
JOIN 
    Livre l ON ex.ISBN = l.ISBN
WHERE 
    l.Genre = 'Science-Fiction' -- Adaptez selon les genres dans votre base
GROUP BY 
    a.IdAdherent, l.Titre, l.Genre
ORDER BY 
    a.Nom, a.Prenom, NombreEmprunts DESC;


