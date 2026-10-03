package mutations

import (
	"errors"
	"testing"
)

type stubMutation struct {
	fn func(schema map[string]any) (MutationResult, error)
}

func (s stubMutation) Mutate(schema map[string]any) (MutationResult, error) {
	return s.fn(schema)
}

func TestMutateSchema_AppliesMutationsInOrderAndMergesTemplateArgs(t *testing.T) {
	schema := map[string]any{"type": "object"}

	first := stubMutation{fn: func(s map[string]any) (MutationResult, error) {
		s["step1"] = true
		return MutationResult{Schema: s, TemplateArgs: map[string]string{"a": "1"}}, nil
	}}
	second := stubMutation{fn: func(s map[string]any) (MutationResult, error) {
		if s["step1"] != true {
			t.Fatalf("expected step1 to have run before step2")
		}
		s["step2"] = true
		return MutationResult{Schema: s, TemplateArgs: map[string]string{"b": "2"}}, nil
	}}

	got, err := MutateSchema([]Mutation{first, second}, schema)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Schema["step1"] != true || got.Schema["step2"] != true {
		t.Errorf("expected both mutations applied, got %#v", got.Schema)
	}
	if got.TemplateArgs["a"] != "1" || got.TemplateArgs["b"] != "2" {
		t.Errorf("expected merged template args, got %#v", got.TemplateArgs)
	}
}

func TestMutateSchema_StopsAndReturnsErrorOnFailure(t *testing.T) {
	wantErr := errors.New("boom")
	ran := false
	failing := stubMutation{fn: func(s map[string]any) (MutationResult, error) {
		return MutationResult{}, wantErr
	}}
	never := stubMutation{fn: func(s map[string]any) (MutationResult, error) {
		ran = true
		return MutationResult{Schema: s}, nil
	}}

	_, err := MutateSchema([]Mutation{failing, never}, map[string]any{})
	if !errors.Is(err, wantErr) {
		t.Fatalf("err = %v, want %v", err, wantErr)
	}
	if ran {
		t.Errorf("expected mutation after the failing one to not run")
	}
}
