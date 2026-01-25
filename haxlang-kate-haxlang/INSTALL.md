# Install: HaxLang syntax highlighting for Kate (KF5)

```sh
mkdir -p ~/.local/share/org.kde.syntax-highlighting/syntax/
cp syntax/haxlang.xml ~/.local/share/org.kde.syntax-highlighting/syntax/
rm -rf ~/.cache/org.kde.syntax-highlighting
```

Restart Kate, then select highlighting mode: `HaxLang`.

This definition is written for KF5/Devuan robustness:
- No keyword-list engine
- Minimal regex use (only for consuming identifier bodies)
- Block comments are `-- ... --`
