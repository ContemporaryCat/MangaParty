package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"mangaparty/db" // Import the generated sqlc package
)

// Server holds the database connection and the sqlc querier.
type Server struct {
	queries *db.Queries
	pool    *pgxpool.Pool
}

func main() {
	// 1. Connect to the database using the URL from the .env file
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is not set")
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatalf("Unable to connect to database: %v\n", err)
	}
	defer pool.Close()

	log.Println("Database connection successful.")

	srv := &Server{
		queries: db.New(pool),
		pool:    pool,
	}

	// 2. Setup API routes
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/person", srv.handleCreatePerson)
	mux.HandleFunc("GET /api/person/{id}", srv.handleGetPerson)
	// Add more handlers here as you build out the API...

	// 3. Start the web server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Server starting on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

// --- API Handlers ---

// CreatePersonRequest defines the JSON payload for creating a new person.
type CreatePersonRequest struct {
	Note       []string `json:"note"`
	Contact    []string `json:"contact_info"`
	Activity   []string `json:"field_of_activity"`
	Language   []string `json:"language"`
	Profession []string `json:"profession"`
}

// handleCreatePerson demonstrates a transaction for the Class Table Inheritance model.
func (s *Server) handleCreatePerson(w http.ResponseWriter, r *http.Request) {
	var req CreatePersonRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	// START TRANSACTION: Creating a person requires 3 inserts, which must all succeed or fail together.
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		http.Error(w, "Failed to begin transaction", http.StatusInternalServerError)
		return
	}
	// Defer a rollback. If the transaction is committed, this is a no-op.
	defer tx.Rollback(ctx)

	// Use the transaction-aware querier
	qtx := s.queries.WithTx(tx)

	// Step 1: Insert into the root table `mp_res`
	res, err := qtx.CreateRes(ctx, db.CreateResParams{
		EntityType: db.MpEntityTypePerson, // This is the enum sqlc generated for you
		Note:       req.Note,
	})
	if err != nil {
		http.Error(w, "Failed to create base resource: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Step 2: Insert into the `mp_agent` table using the ID from the root table
	err = qtx.CreateAgent(ctx, db.CreateAgentParams{
		ID:              res.ID,
		ContactInfo:     req.Contact,
		FieldOfActivity: req.Activity,
		Language:        req.Language,
	})
	if err != nil {
		http.Error(w, "Failed to create agent: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Step 3: Insert into the `mp_person` table
	err = qtx.CreatePerson(ctx, db.CreatePersonParams{
		ID:         res.ID,
		Profession: req.Profession,
	})
	if err != nil {
		http.Error(w, "Failed to create person: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// COMMIT TRANSACTION: If all steps were successful, commit the changes.
	if err := tx.Commit(ctx); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{"id": res.ID, "status": "created"})
}

func (s *Server) handleGetPerson(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	personID, err := uuid.Parse(idStr)
	if err != nil {
		http.Error(w, "Invalid UUID format", http.StatusBadRequest)
		return
	}

	person, err := s.queries.GetPerson(r.Context(), pgtype.UUID{Bytes: personID, Valid: true})
	if err != nil {
		// Use pgx to check for a "no rows" error specifically
		if err.Error() == "no rows in result set" {
			http.Error(w, "Person not found", http.StatusNotFound)
			return
		}
		http.Error(w, "Database error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(person)
}
