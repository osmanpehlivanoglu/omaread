#include <QFile>
#include <QFileInfo>
#include <QColor>
#include <QFont>
#include <QGuiApplication>
#include <QApplication>
#include <QCoreApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickTextDocument>
#include <QProcess>
#include <QPrintDialog>
#include <QPrinter>
#include <QRegularExpression>
#include <QSet>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>
#include <QTextFrame>
#include <QTextFragment>
#include <QTextList>
#include <QSyntaxHighlighter>
#include <QTextTable>
#include <QTimer>
#include <QUrl>
#include <QDir>
#include <functional>

class SearchHighlighter : public QSyntaxHighlighter {
public:
    explicit SearchHighlighter(QTextDocument *document) : QSyntaxHighlighter(document) {}

    void setSearch(const QString &text, int currentStart, bool darkMode) {
        if (query == text && selectedStart == currentStart && dark == darkMode) return;
        const bool sameQuery = query == text && dark == darkMode;
        const int previousStart = selectedStart;
        query = text;
        selectedStart = currentStart;
        dark = darkMode;
        if (!sameQuery) {
            rehighlight();
        } else {
            if (previousStart >= 0) rehighlightBlock(document()->findBlock(previousStart));
            if (selectedStart >= 0 && document()->findBlock(selectedStart) != document()->findBlock(previousStart))
                rehighlightBlock(document()->findBlock(selectedStart));
        }
    }

protected:
    void highlightBlock(const QString &text) override {
        if (query.isEmpty()) return;
        int from = 0;
        while ((from = text.indexOf(query, from, Qt::CaseInsensitive)) >= 0) {
            QTextCharFormat format;
            const bool current = currentBlock().position() + from == selectedStart;
            format.setBackground(QColor(current ? (dark ? "#b36b20" : "#ffad42")
                                                : (dark ? "#725b18" : "#ffe58a")));
            setFormat(from, query.size(), format);
            from += query.size();
        }
    }

private:
    QString query;
    int selectedStart = -1;
    bool dark = true;
};

class Reader : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString content READ content NOTIFY changed)
    Q_PROPERTY(QString fileName READ fileName NOTIFY changed)
    Q_PROPERTY(bool hasFile READ hasFile NOTIFY changed)
    Q_PROPERTY(QUrl fileUrl READ fileUrl NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(int wordCount READ wordCount NOTIFY changed)
    Q_PROPERTY(QString background READ background NOTIFY changed)
    Q_PROPERTY(QString foreground READ foreground NOTIFY changed)
    Q_PROPERTY(QString accent READ accent NOTIFY changed)
    Q_PROPERTY(QString selection READ selection NOTIFY changed)
    Q_PROPERTY(bool darkMode READ darkMode NOTIFY changed)
    Q_PROPERTY(QVariantList markers READ markers NOTIFY markersChanged)
public:
    Reader() {
        loadTheme();
        connect(&poller, &QTimer::timeout, this, [this] {
            loadTheme();
            if (!path.isEmpty()) loadFile(path, false);
        });
        poller.start(1000);
    }
    QString content() const { return text; }
    QString fileName() const { return path.isEmpty() ? QStringLiteral("Open a Markdown file") : QFileInfo(path).fileName(); }
    bool hasFile() const { return !path.isEmpty(); }
    QUrl fileUrl() const { return QUrl::fromLocalFile(path); }
    QString status() const { return message; }
    int wordCount() const {
        QRegularExpression words(QStringLiteral("[\\p{L}\\p{N}]+(?:['-][\\p{L}\\p{N}]+)*"));
        auto matches = words.globalMatch(text);
        int count = 0;
        while (matches.hasNext()) { matches.next(); ++count; }
        return count;
    }
    QString background() const { return bg; }
    QString foreground() const { return fg; }
    QString accent() const { return highlight; }
    QString selection() const { return select; }
    bool darkMode() const { return dark; }
    QVariantList markers() const { return listMarkers; }

    Q_INVOKABLE void open(const QUrl &url) {
        if (!url.isLocalFile()) {
            message = QStringLiteral("Only local files can be opened");
            emit changed();
            return;
        }
        loadFile(url.toLocalFile(), true);
    }
    Q_INVOKABLE void reload() { if (!path.isEmpty()) loadFile(path, true); }
    Q_INVOKABLE void edit() {
        if (path.isEmpty()) return;
        if (!QProcess::startDetached(QStringLiteral("omawrite"), {path})) {
            message = QStringLiteral("Could not open Omawrite");
            emit changed();
        }
    }
    Q_INVOKABLE void newWindow() {
        if (!QProcess::startDetached(QCoreApplication::applicationFilePath(), {})) {
            message = QStringLiteral("Could not open a new window");
            emit changed();
        }
    }
    Q_INVOKABLE void printDocument() {
        if (!document || path.isEmpty()) return;
        QPrinter printer(QPrinter::HighResolution);
        printer.setDocName(fileName());
        QPrintDialog dialog(&printer);
        dialog.setWindowTitle(QStringLiteral("Print %1").arg(fileName()));
        if (dialog.exec() != QDialog::Accepted) return;
        QTextDocument printable;
        printable.setDefaultFont(QFont(QStringLiteral("iA Writer Mono S"), 12));
        printable.setBaseUrl(QUrl::fromLocalFile(path));
        printable.setMarkdown(text);
        printable.print(&printer);
    }
    Q_INVOKABLE void attachDocument(QObject *quickDocument) {
        auto *wrapper = qobject_cast<QQuickTextDocument *>(quickDocument);
        document = wrapper ? wrapper->textDocument() : nullptr;
        if (document) searchHighlighter = new SearchHighlighter(document);
    }
    Q_INVOKABLE QVariantList findAllText(const QString &query) const {
        QVariantList matches;
        if (!document || query.isEmpty()) return matches;
        for (QTextBlock block = document->begin(); block.isValid(); block = block.next()) {
            const QString text = block.text();
            int from = 0;
            while ((from = text.indexOf(query, from, Qt::CaseInsensitive)) >= 0) {
                matches.append(QVariantMap{{QStringLiteral("start"), block.position() + from},
                                           {QStringLiteral("end"), block.position() + from + query.size()}});
                from += query.size();
            }
        }
        return matches;
    }
    Q_INVOKABLE void highlightSearch(const QString &query, int currentStart) {
        searchQuery = query;
        searchCurrent = currentStart;
        if (searchHighlighter) searchHighlighter->setSearch(query, currentStart, dark);
    }
    Q_INVOKABLE void styleDocument(int pixelSize) {
        if (!document || styling) return;
        styledPixelSize = pixelSize;
        styling = true;
        const QColor marker = dark ? QColor(QStringLiteral("#4f525a"))
                                   : QColor(QStringLiteral("#aeb1b5"));
        const QColor body(fg), link(highlight);
        QSet<QTextList *> styledLists;
        QVariantList newMarkers;
        for (QTextBlock block = document->begin(); block.isValid(); block = block.next()) {
            const int headingLevel = block.blockFormat().headingLevel();
            const qreal headingScale[] = {1.0, 1.70, 1.45, 1.30, 1.18, 1.09, 1.0};
            const int textSize = headingLevel >= 1 && headingLevel <= 6
                ? qRound(pixelSize * headingScale[headingLevel]) : pixelSize;
            QTextCursor blockCursor(block);
            QTextBlockFormat blockStyle;
            blockStyle.setLineHeight(140, QTextBlockFormat::ProportionalHeight);
            blockStyle.setBottomMargin(block.textList() ? 8 : headingLevel ? 20 : 16);
            blockCursor.mergeBlockFormat(blockStyle);

            if (QTextList *list = block.textList(); list && !styledLists.contains(list)) {
                QTextListFormat format = list->format();
                format.setForeground(marker);
                list->setFormat(format);
                styledLists.insert(list);
            }
            if (QTextList *list = block.textList()) {
                QString label = list->itemText(block);
                switch (list->format().style()) {
                case QTextListFormat::ListDisc: label = QStringLiteral("•"); break;
                case QTextListFormat::ListCircle: label = QStringLiteral("◦"); break;
                case QTextListFormat::ListSquare: label = QStringLiteral("▪"); break;
                default: break;
                }
                newMarkers.append(QVariantMap{{QStringLiteral("position"), block.position()},
                                              {QStringLiteral("label"), label}});
            }
            for (auto it = block.begin(); !it.atEnd(); ++it) {
                const QTextFragment fragment = it.fragment();
                if (!fragment.isValid()) continue;
                QTextCharFormat format = fragment.charFormat();
                format.setForeground(fragment.charFormat().isAnchor() ? link : body);
                format.setFontFamilies({QStringLiteral("iA Writer Mono S")});
                format.clearProperty(QTextFormat::FontSizeAdjustment);
                format.setProperty(QTextFormat::FontPixelSize, textSize);
                if (fragment.charFormat().isAnchor()) format.setFontUnderline(true);
                QTextCursor cursor(document);
                cursor.setPosition(fragment.position());
                cursor.setPosition(fragment.position() + fragment.length(), QTextCursor::KeepAnchor);
                cursor.setCharFormat(format);
            }
        }
        const std::function<void(QTextFrame *)> styleTables = [&](QTextFrame *frame) {
            for (QTextFrame *child : frame->childFrames()) {
                if (auto *table = qobject_cast<QTextTable *>(child)) {
                    QTextTableFormat tableFormat = table->format();
                    tableFormat.setBorderBrush(marker);
                    table->setFormat(tableFormat);
                    for (int row = 0; row < table->rows(); ++row) {
                        for (int column = 0; column < table->columns(); ++column) {
                            QTextTableCell cell = table->cellAt(row, column);
                            QTextTableCellFormat cellFormat = cell.format().toTableCellFormat();
                            cellFormat.setBorderBrush(marker);
                            cell.setFormat(cellFormat);
                        }
                    }
                }
                styleTables(child);
            }
        };
        styleTables(document->rootFrame());
        listMarkers = newMarkers;
        emit markersChanged();
        styling = false;
    }

signals:
    void changed();
    void markersChanged();

private:
    void loadFile(const QString &filePath, bool force) {
        QFileInfo info(filePath);
        if (!force && info.exists() && info.lastModified() == stamp && info.size() == size) return;
        QFile file(filePath);
        if (!file.open(QIODevice::ReadOnly)) {
            if (!force && message == QStringLiteral("File unavailable")) return;
            message = QStringLiteral("File unavailable");
            emit changed();
            return;
        }
        const QString fresh = QString::fromUtf8(file.readAll());
        path = info.absoluteFilePath();
        stamp = info.lastModified();
        size = info.size();
        text = fresh;
        message = QStringLiteral("Opened %1").arg(info.fileName());
        emit changed();
        QTimer::singleShot(0, this, [this] { styleDocument(styledPixelSize); });
    }
    void loadTheme() {
        const QString themePath = QDir::homePath() + QStringLiteral("/.local/state/omarchy/current/theme/colors.toml");
        QFile file(themePath);
        QString newBg = QStringLiteral("#101010"), newFg = QStringLiteral("#eeeeee");
        QString newAccent = QStringLiteral("#5584aa"), newSelection = QStringLiteral("#186a9a");
        QString mode;
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            while (!file.atEnd()) {
                const QString line = QString::fromUtf8(file.readLine()).trimmed();
                if (line.startsWith('#')) continue;
                const int equals = line.indexOf('=');
                if (equals < 0) continue;
                const QString key = line.left(equals).trimmed();
                QString value = line.mid(equals + 1).trimmed();
                if (value.size() >= 2 && (value.front() == '"' || value.front() == '\'')) value = value.mid(1, value.size() - 2);
                if (key == QStringLiteral("mode")) mode = value;
                else if (key == QStringLiteral("background")) newBg = value;
                else if (key == QStringLiteral("foreground")) newFg = value;
                else if (key == QStringLiteral("accent")) newAccent = value;
                else if (key == QStringLiteral("selection")) newSelection = value;
            }
        }
        const bool newDark = mode == QStringLiteral("dark") || (mode != QStringLiteral("light") && QColor(newBg).lightnessF() < 0.5);
        if (bg == newBg && fg == newFg && highlight == newAccent && select == newSelection && dark == newDark) return;
        bg = newBg; fg = newFg; highlight = newAccent; select = newSelection; dark = newDark;
        if (searchHighlighter) searchHighlighter->setSearch(searchQuery, searchCurrent, dark);
        emit changed();
        QTimer::singleShot(0, this, [this] { styleDocument(styledPixelSize); });
    }
    QString path, text, message, bg, fg, highlight, select;
    QDateTime stamp;
    qint64 size = -1;
    bool dark = true;
    QTimer poller;
    QPointer<QTextDocument> document;
    QPointer<SearchHighlighter> searchHighlighter;
    QString searchQuery;
    int searchCurrent = -1;
    bool styling = false;
    int styledPixelSize = 20;
    QVariantList listMarkers;
};

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Omaread"));
    app.setDesktopFileName(QStringLiteral("omaread"));
    if (argc > 2) {
        qCritical("Usage: omaread [FILE]");
        return 2;
    }
    Reader reader;
    if (argc == 2) reader.open(QUrl::fromLocalFile(QFileInfo(QString::fromLocal8Bit(argv[1])).absoluteFilePath()));
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("reader"), &reader);
    engine.load(QUrl(QStringLiteral("qrc:/Main.qml")));
    if (engine.rootObjects().isEmpty()) return 1;
    return app.exec();
}

#include "main.moc"
