# API (Go) — placeholder

Not part of iteration 1. The shopping-list MVP talks directly to Supabase, secured by
Row-Level Security.

This service will be introduced for the **budgeting** iteration to own heavier business
logic (aggregation, reporting, recurring transactions). It will sit behind the same
Supabase-issued JWT, verifying tokens against Supabase's JWKS endpoint, while the mobile
app continues to use Supabase for auth and the shopping list.
