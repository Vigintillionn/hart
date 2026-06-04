class HelpStore {
  open = $state(false);
  group = $state<string>("all");
  query = $state("");

  public get q(): string {
    return this.query.trim().toLowerCase();
  }

  public show() {
    this.open = true;
  }

  public close() {
    this.open = false;
    this.query = "";
  }

  public toggle() {
    if (this.open) this.close();
    else this.show();
  }

  public select(group: string) {
    this.group = group;
  }
}

export const helpStore = new HelpStore();
