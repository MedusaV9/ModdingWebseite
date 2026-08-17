import Foundation

// W5 games client (28#2/#3/#5): keeps the app-wide "Du bist dran!" badge
// live from the game socket events (B-16) and turns game endings into
// attributed moments (declined invitation, forfeit hand-over). Split out of
// AppState.swift like RitualsAppState/AppStatePlatform so the parallel work
// packages don't collide in one file.

extension AppState {

    /// Called from `handlePlatformEvent` for the four game event types.
    /// `gamesAwaitingMe` used to refresh only with the inbox digest at
    /// socket-welcome — the play-tab badge was almost always stale (B-16).
    /// Turn attribution follows the server verdict (`turnMemberId` in the
    /// v12 `game_move` frame / the fetched session) and falls back to the
    /// old last-mover heuristic only against pre-v12 servers.
    func handleGameEvent(_ event: ServerEvent) {
        switch event.type {
        case .gameCreated:
            guard let game = event.decode(GameOnlyResponse.self)?.game else { return }
            if game.state == "lobby" && game.createdBy != memberId {
                upsertAwaitingGame(id: game.id, type: game.type)
            } else {
                removeAwaitingGame(id: game.id)
            }
        case .gameStarted:
            // The invitation is resolved and nobody has moved yet.
            guard let game = event.decode(GameOnlyResponse.self)?.game else { return }
            removeAwaitingGame(id: game.id)
        case .gameMove:
            guard let payload = event.decode(GameMovePayload.self) else { return }
            // v12 frames name the post-move turn holder — an extra move
            // keeps the badge with the mover instead of flipping it to the
            // "last player" heuristic. Pre-v12 frames (field missing) keep
            // the old mover-based guess; either way the badge is verified
            // against the fetched session before it appears.
            let maybeMyTurn: Bool
            switch payload.turnMemberId {
            case .some(let verdict): maybeMyTurn = verdict == memberId
            case .none: maybeMyTurn = payload.move.memberId != memberId
            }
            if maybeMyTurn {
                markAwaitingAfterMove(gameId: payload.gameId)
            } else {
                removeAwaitingGame(id: payload.gameId)
            }
        case .gameEnded:
            guard let game = event.decode(GameOnlyResponse.self)?.game else { return }
            removeAwaitingGame(id: game.id)
            noteGameEnding(game)
        default:
            break
        }
    }

    // MARK: Badge bookkeeping

    private func upsertAwaitingGame(id: String, type: String) {
        guard !gamesAwaitingMe.contains(where: { $0.gameId == id }) else { return }
        gamesAwaitingMe.append(.init(gameId: id, type: type))
    }

    private func removeAwaitingGame(id: String) {
        gamesAwaitingMe.removeAll { $0.gameId == id }
    }

    /// A move probably made it my turn. The move frame carries no game
    /// type, so the session is verified once against the server — the
    /// fetched session's own three-state `turnMemberId` (contract v11/v12)
    /// is even fresher than the frame's verdict, and the fetch also
    /// filters ended games racing the socket.
    private func markAwaitingAfterMove(gameId: String) {
        guard !gamesAwaitingMe.contains(where: { $0.gameId == gameId }),
              let api else { return }
        Task { [weak self] in
            let game: GameSession
            do {
                game = try await api.game(id: gameId)
            } catch {
                return  // offline or racing an ended game — the inbox catches up
            }
            guard let self,
                  GameTurnRules.awaitingMe(state: game.state,
                                           createdBy: game.createdBy,
                                           turnVerdict: game.turnMemberId,
                                           lastMoveMemberId: game.moves.last?.memberId,
                                           myId: self.memberId) else { return }
            self.upsertAwaitingGame(id: game.id, type: game.type)
        }
    }

    // MARK: Ending moments

    /// Attributed endings: a declined invitation tells the creator gently
    /// (28#5), a forfeit tells the winner the point is theirs (28#3).
    private func noteGameEnding(_ game: GameSession) {
        if game.result?["declined"]?.boolValue == true {
            if game.result?["by"]?.stringValue != memberId, game.createdBy == memberId {
                showToast(L10n.t("games.invite.declinedToast", ["name": partnerName]),
                          style: .info)
            }
        } else if let by = game.result?["forfeitBy"]?.stringValue, by != memberId {
            showToast(L10n.t("games.forfeit.partnerToast", ["name": partnerName]),
                      style: .love)
            SoundEngine.shared.play(.tada)
        }
    }
}
