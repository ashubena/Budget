import SwiftUI
import SwiftData

/// Main chat surface — primary interaction with the app.
/// Type expenses, income, or loan operations like:
///   "500 food"               → expense
///   "got 80000 salary"       → income
///   "lent ahmed 10000"       → loan out
///   "borrowed 5000 from sara" → loan in
///   "ahmed paid back 5000"   → loan payment incoming
///   "paid back sara 2000"    → loan payment outgoing
struct ChatView: View {
    @Environment(\.modelContext) private var context

    @State private var input: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var pendingCategoryFragment: String? = nil
    @State private var pendingTransactionID: UUID? = nil

    @FocusState private var inputFocused: Bool

    #if os(iOS)
    @State private var speech = SpeechService()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputBar
        }
        .navigationTitle("Budget")
        .task {
            SeedData.seedIfNeeded(context: context)
            if messages.isEmpty {
                messages.append(.system("Hi. Try “500 food”, “got 80000 salary”, or “lent ahmed 5000”."))
            }
        }
    }

    // MARK: - Pieces

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { msg in
                        MessageBubble(message: msg).id(msg.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit(submit)
                .submitLabel(.send)
            #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            #endif

            #if os(iOS)
            micButton
            #endif

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var placeholder: String {
        #if os(iOS)
        if speech.isRecording { return "Listening…" }
        #endif
        if pendingCategoryFragment != nil { return "Reply with a category…" }
        return "e.g. 500 food"
    }

    // MARK: - Mic (iOS)

    #if os(iOS)
    @ViewBuilder
    private var micButton: some View {
        Button {
            toggleSpeech()
        } label: {
            Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.title2)
                .foregroundStyle(speech.isRecording ? Color.red : Color.accentColor)
        }
        .buttonStyle(.borderless)
        .onChange(of: speech.transcript) { _, new in
            if speech.isRecording {
                input = new
            }
        }
    }

    private func toggleSpeech() {
        if speech.isRecording {
            let final = speech.stopRecording()
            if !final.isEmpty {
                input = final
                inputFocused = true
            }
        } else {
            Task {
                if !speech.isAuthorized {
                    await speech.requestAuthorization()
                }
                if speech.isAuthorized {
                    speech.startRecording()
                } else if let err = speech.error {
                    messages.append(.system(err))
                }
            }
        }
    }
    #endif

    // MARK: - Submit

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(.user(text))

        if let fragment = pendingCategoryFragment, let txnID = pendingTransactionID {
            handleCategoryClarification(text, originalFragment: fragment, transactionID: txnID)
            return
        }

        do {
            let parsed = try Parser.parse(text)
            let service = TransactionService(context: context)
            let logResult = try service.log(parsed.result, occurredAt: parsed.occurredAt)
            var responseMessage = logResult.message
            if let phrase = parsed.datePhrase {
                responseMessage += "\n📅 dated: \(phrase)"
            }
            messages.append(.system(responseMessage))
            if logResult.needsCategoryFollowUp {
                pendingCategoryFragment = logResult.unresolvedFragment
                pendingTransactionID = logResult.transactionID
            }
        } catch let err as ParserError {
            messages.append(.system(err.localizedDescription))
        } catch {
            messages.append(.system("Couldn't log that: \(error.localizedDescription)"))
        }
    }

    // MARK: - Category clarification

    private func handleCategoryClarification(_ reply: String, originalFragment: String, transactionID: UUID) {
        let categoryName = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            pendingCategoryFragment = nil
            pendingTransactionID = nil
        }

        do {
            let target = categoryName.lowercased()
            let allCats = try context.fetch(FetchDescriptor<Category>())
            let category: Category
            if let existing = allCats.first(where: { $0.name.lowercased() == target }) {
                category = existing
            } else {
                category = Category(name: categoryName, kind: .expense)
                context.insert(category)
            }

            let txID = transactionID
            let txns = try context.fetch(
                FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == txID })
            )
            guard let txn = txns.first else {
                messages.append(.system("Hmm, couldn't find that transaction to update."))
                return
            }
            txn.category = category
            txn.needsCategory = false

            context.insert(CategoryAlias(
                alias: originalFragment,
                category: category,
                source: .learned
            ))

            try context.save()
            messages.append(.system("Got it. \"\(originalFragment)\" → \(category.name) (will remember)."))
        } catch {
            messages.append(.system("Couldn't save that: \(error.localizedDescription)"))
        }
    }
}

// MARK: - Message model

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, system }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp = Date()

    static func user(_ text: String) -> ChatMessage { .init(role: .user, text: text) }
    static func system(_ text: String) -> ChatMessage { .init(role: .system, text: text) }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 32) }
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .frame(maxWidth: 480, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .system { Spacer(minLength: 32) }
        }
    }

    private var bubbleBackground: Color {
        message.role == .user ? .accentColor : Color.gray.opacity(0.2)
    }
}

#Preview {
    NavigationStack {
        ChatView()
    }
    .modelContainer(for: [
        Account.self, Category.self, CategoryKeyword.self, CategoryAlias.self,
        Tag.self, Transaction.self, TransactionAudit.self, Bucket.self,
        Allocation.self, BucketPeriod.self, Plan.self, PlanInstance.self, Loan.self,
    ], inMemory: true)
}
