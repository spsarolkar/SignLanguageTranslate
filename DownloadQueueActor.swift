func markFailed(_ id: UUID, error errorMessage: String) {
      guard var task = tasks[id] else { return }

      // Update the task directly instead of using updateTask closure
      let previousActiveCount = getActiveCount()
      task.fail(with: errorMessage)
      tasks[id] = task

      let newActiveCount = getActiveCount()
      let updatedTask = task
      let message = errorMessage

      notifyDelegate { delegate in
          delegate.queueDidUpdateTask(updatedTask)
          if previousActiveCount != newActiveCount {
              delegate.queueDidChangeActiveCount(newActiveCount)
          }
          delegate.queueDidFailTask(updatedTask, error: message)
      }
  }