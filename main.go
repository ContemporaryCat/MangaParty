package main

import (
	"context"
	"encoding/json"
	"html/template"
	"log"
	"net/http"
	"os"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"

	"mangaparty/db" // Import the generated sqlc package
)

// Server holds the database connection and the sqlc querier.
type Server struct {
	queries *db.Queries
	pool    *pgxpool.Pool
	tmpl    *template.Template
}

func main() {
	// Determine environment
	env := os.Getenv("APP_ENV")
	if env == "" {
		env = "development"
	}

	// Load .env files (local first, then default)
	// godotenv.Load will not overwrite existing env vars, so if we load .env.local first,
	// its values will be preserved.
	if err := godotenv.Load(".env.local", ".env"); err != nil {
		log.Println("No .env file found (or error loading it)")
	}

	log.Println("------------------------------------------------")
	log.Printf("   Running in %s mode", env)
	log.Println("------------------------------------------------")

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

	// Parse templates
	tmpl, err := template.ParseGlob("templates/*.html")
	if err != nil {
		log.Fatalf("Failed to parse templates: %v", err)
	}

	srv := &Server{
		queries: db.New(pool),
		pool:    pool,
		tmpl:    tmpl,
	}

	// 2. Setup API routes
	mux := http.NewServeMux()

	// Static files
	fs := http.FileServer(http.Dir("static"))
	mux.Handle("/static/", http.StripPrefix("/static/", fs))

	// Frontend Routes
	mux.HandleFunc("GET /{$}", srv.handleIndex)
	mux.HandleFunc("GET /people", srv.handleListPeople)
	mux.HandleFunc("GET /people/new", srv.handleNewPerson)
	mux.HandleFunc("GET /works", srv.handleListWorks)
	mux.HandleFunc("GET /works/new", srv.handleNewWork)

	// API Routes
	mux.HandleFunc("POST /api/person", srv.handleCreatePerson)
	mux.HandleFunc("GET /api/person/{id}", srv.handleGetPerson)
	mux.HandleFunc("POST /api/work", srv.handleCreateWork)
	// Add more handlers here as you build out the API...

	// 3. Start the web server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Server starting on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

// --- Frontend Handlers ---

func (s *Server) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	s.render(w, "index.html", nil)
}

func (s *Server) handleListPeople(w http.ResponseWriter, r *http.Request) {
	people, err := s.queries.ListPeople(r.Context())
	if err != nil {
		http.Error(w, "Failed to fetch people: "+err.Error(), http.StatusInternalServerError)
		return
	}
	s.render(w, "person_list.html", people)
}

func (s *Server) handleNewPerson(w http.ResponseWriter, r *http.Request) {
	s.render(w, "person_create.html", nil)
}

func (s *Server) handleListWorks(w http.ResponseWriter, r *http.Request) {
	works, err := s.queries.ListWorks(r.Context())
	if err != nil {
		http.Error(w, "Failed to fetch works: "+err.Error(), http.StatusInternalServerError)
		return
	}
	s.render(w, "work_list.html", works)
}

func (s *Server) handleNewWork(w http.ResponseWriter, r *http.Request) {
	s.render(w, "work_create.html", nil)
}

func (s *Server) render(w http.ResponseWriter, name string, data interface{}) {
	// Clone the template to ensure thread safety if we were modifying it,
	// but for simple execution it's fine.
	// We execute the "base.html" template, which invokes the "content" block defined in the specific page template.
	// However, Go templates don't work exactly like inheritance.
	// We need to execute the specific template which defines "content" AND includes base?
	// Actually, the common pattern is to execute the base template, and pass the data.
	// But the base template needs to know which "content" block to use.
	// Since we parsed all glob, they are all in s.tmpl.
	// If we define "content" in multiple files, the last one parsed wins if they share the name "content".
	// To fix this, we should parse them per request or use distinct block names.
	// OR, better for this simple app: Parse base + specific file for each handler.
	// Let's refactor the ParseGlob approach to a per-request parse for simplicity and correctness with "content" blocks.

	// Re-parsing for simplicity in this demo. In prod, use a map of pre-parsed templates.
	t, err := template.ParseFiles("templates/base.html", "templates/"+name)
	if err != nil {
		http.Error(w, "Template error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	err = t.Execute(w, data)
	if err != nil {
		log.Printf("Template execution error: %v", err)
	}
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

// CreateWorkRequest defines the JSON payload for creating a new work.
type CreateWorkRequest struct {
	Note                     []string        `json:"note"`
	Category                 []string        `json:"category"`
	RepresentativeAttributes json.RawMessage `json:"representative_attributes"` // JSONB
}

func (s *Server) handleCreateWork(w http.ResponseWriter, r *http.Request) {
	var req CreateWorkRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	ctx := r.Context()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		http.Error(w, "Failed to begin transaction", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(ctx)

	qtx := s.queries.WithTx(tx)

	// Step 1: Insert into mp_res
	res, err := qtx.CreateRes(ctx, db.CreateResParams{
		EntityType: db.MpEntityTypeWork,
		Note:       req.Note,
	})
	if err != nil {
		http.Error(w, "Failed to create base resource: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Step 2: Insert into mp_work
	err = qtx.CreateWork(ctx, db.CreateWorkParams{
		ID:                       res.ID,
		Category:                 req.Category,
		RepresentativeAttributes: req.RepresentativeAttributes,
	})
	if err != nil {
		http.Error(w, "Failed to create work: "+err.Error(), http.StatusInternalServerError)
		return
	}

	if err := tx.Commit(ctx); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{"id": res.ID, "status": "created"})
}
