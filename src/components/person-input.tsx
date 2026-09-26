import { useEffect, useMemo, useState } from "react";
import {
  Combobox,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxInput,
  ComboboxItem,
  ComboboxList,
} from "@productivity-os/shared-ui/components/ui/combobox";
import type { PersonRecord } from "@/api/notebook-data";
import type { CardPluginHostServices } from "@/plugins/plugin-api";

type Props = {
  personId: string | null;
  name: string;
  services: CardPluginHostServices;
  invalid?: boolean;
  onChange(personId: string | null, name: string): void;
};

const normalize = (value: string) => value.trim().toLocaleLowerCase();

export function PersonInput({
  personId,
  name,
  services,
  invalid,
  onChange,
}: Props) {
  const [people, setPeople] = useState<PersonRecord[]>([]);
  const [query, setQuery] = useState(name);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => setQuery(name), [name]);
  useEffect(() => {
    let cancelled = false;
    void services
      .listPersons()
      .then((items) => !cancelled && setPeople(items))
      .catch(
        (cause) =>
          !cancelled &&
          setError(cause instanceof Error ? cause.message : String(cause)),
      );
    return () => {
      cancelled = true;
    };
  }, [services]);

  const selected = useMemo(
    () => people.find((person) => person.id === personId) ?? null,
    [people, personId],
  );
  const exact = people.find(
    (person) => normalize(person.name) === normalize(query),
  );

  const create = async () => {
    const nextName = query.trim();
    if (!nextName || creating) return;
    if (exact) {
      onChange(exact.id, exact.name);
      setQuery(exact.name);
      return;
    }
    setCreating(true);
    setError(null);
    try {
      const person = await services.savePerson({
        id: crypto.randomUUID(),
        name: nextName,
        role: "",
        organization: "",
        notes: "",
      });
      setPeople((current) =>
        current.some((item) => item.id === person.id)
          ? current
          : [...current, person],
      );
      setQuery(person.name);
      onChange(person.id, person.name);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setCreating(false);
    }
  };

  return (
    <Combobox<PersonRecord>
      items={people}
      value={selected}
      inputValue={query}
      itemToStringLabel={(person) => person.name}
      itemToStringValue={(person) => person.id}
      isItemEqualToValue={(person, value) => person.id === value.id}
      onInputValueChange={(value) => {
        setError(null);
        setQuery(value);
        const match = people.find(
          (person) => normalize(person.name) === normalize(value),
        );
        onChange(match?.id ?? null, value);
      }}
      onValueChange={(person) => {
        if (!person) return;
        setQuery(person.name);
        onChange(person.id, person.name);
      }}
    >
      <ComboboxInput
        placeholder="Search or create a person"
        aria-invalid={invalid || undefined}
        disabled={creating}
        showClear={Boolean(query)}
        onKeyDown={(event) => {
          if (event.key !== "Enter" || exact) return;
          event.preventDefault();
          void create();
        }}
      />
      <ComboboxContent>
        <ComboboxList>
          <ComboboxEmpty>
            {query.trim()
              ? `Press Enter to create “${query.trim()}”`
              : "No people found"}
          </ComboboxEmpty>
          {people.map((person) => (
            <ComboboxItem key={person.id} value={person}>
              <span>{person.name}</span>
              {(person.role || person.organization) && (
                <small>
                  {[person.role, person.organization]
                    .filter(Boolean)
                    .join(" · ")}
                </small>
              )}
            </ComboboxItem>
          ))}
        </ComboboxList>
      </ComboboxContent>
      {error && <small className="card-editor-field-error">{error}</small>}
    </Combobox>
  );
}
