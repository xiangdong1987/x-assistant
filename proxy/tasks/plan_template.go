package tasks

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const planTemplate = `# Task Plan

## Overview
**任务ID:** {{taskId}}
**任务标题:** {{taskTitle}}
**项目:** {{projectName}}
**路径:** {{projectPath}}
**技术栈:** {{techStack}}
**优先级:** {{priority}}
**状态:** {{status}}
**负责人:** {{assignee}}

**需求描述:**
{{description}}

**预期产出:**
{{expectedOutput}}

## Execution Log

**Agent 说明：** 执行当前阶段时，请在本文件对应阶段下将已完成项从 - [ ] 改为 - [x]，并可在该阶段末尾追加 - [x] 时间: 简要说明 记录进度；阶段内所有项勾选后，系统会据此判定该阶段完成并可能触发下一阶段。

### Plan 阶段
- [x] {{generatedAt}}: Plan生成

### Code 阶段
- [ ] 开发开始（环境准备完成）
- [ ] 代码实现（核心功能完成）

### Test 阶段
- [ ] 测试完成（通过所有测试）

### Done 阶段
- [ ] 代码审查（通过审查）
- [ ] 人工确认完成（最终验收）


## 沟通记录
<!-- 记录重要的沟通和决策 -->

## 问题跟踪
<!-- 记录遇到的问题和解决方案 -->

## Result Summary
<!-- 完成后填写实现总结 -->

---

meta:
  taskId: {{taskId}}
  status: planning
  phase: plan
  notifyOn: implemented
  owner: {{owner}}
  projectKey: {{projectKey}}
  projectName: {{projectName}}
  projectPath: {{projectPath}}
  techStack: {{techStackJson}}
  priority: {{priority}}
  assignee: {{assignee}}
  estimatedHours:
  actualHours: 0
  startedAt: null
  completedAt: null
  createdAt: {{createdAt}}
  updatedAt: {{updatedAt}}
  planVersion: 2.0
  templateUsed: plan-template.md
---
`

// PlanTemplateVars holds the variables for plan template rendering
type PlanTemplateVars struct {
	TaskID       string
	TaskTitle    string
	ProjectName  string
	ProjectPath  string
	ProjectKey   string
	TechStack    []string
	Priority     string
	Status       string
	Assignee     string
	Owner        string
	Description  string
}

// RenderPlanTemplate fills in the plan template with the given variables
func RenderPlanTemplate(vars PlanTemplateVars) string {
	now := time.Now().Format(time.RFC3339)
	techStackStr := strings.Join(vars.TechStack, ", ")
	techStackJSON := "[]"
	if len(vars.TechStack) > 0 {
		items := make([]string, len(vars.TechStack))
		for i, s := range vars.TechStack {
			items[i] = fmt.Sprintf("%q", s)
		}
		techStackJSON = "[" + strings.Join(items, ", ") + "]"
	}

	replacements := map[string]string{
		"{{taskId}}":         vars.TaskID,
		"{{taskTitle}}":      vars.TaskTitle,
		"{{projectName}}":    vars.ProjectName,
		"{{projectPath}}":    vars.ProjectPath,
		"{{projectKey}}":     vars.ProjectKey,
		"{{techStack}}":      techStackStr,
		"{{techStackJson}}":  techStackJSON,
		"{{priority}}":       vars.Priority,
		"{{status}}":         "planning",
		"{{assignee}}":       vars.Assignee,
		"{{owner}}":          vars.Owner,
		"{{description}}":    vars.Description,
		"{{expectedOutput}}": "按计划实现并通过验收",
		"{{generatedAt}}":    now,
		"{{estimatedHours}}": "",
		"{{createdAt}}":      now,
		"{{updatedAt}}":      now,
	}

	result := planTemplate
	for placeholder, value := range replacements {
		result = strings.ReplaceAll(result, placeholder, value)
	}
	return result
}

// WritePlanToProject writes a plan file to the project's docs/ directory.
// Returns the full path of the created plan file.
func WritePlanToProject(projectPath, taskID string, vars PlanTemplateVars) (string, error) {
	docsDir := filepath.Join(projectPath, "docs")
	if err := os.MkdirAll(docsDir, 0755); err != nil {
		return "", fmt.Errorf("create docs dir: %w", err)
	}

	planFileName := fmt.Sprintf("plan-%s.md", taskID)
	planPath := filepath.Join(docsDir, planFileName)
	content := RenderPlanTemplate(vars)

	if err := os.WriteFile(planPath, []byte(content), 0644); err != nil {
		return "", fmt.Errorf("write plan file: %w", err)
	}

	return planPath, nil
}

// GenerateTaskID creates a display task ID in format TASK-YYYYMMDD-NNN
func GenerateTaskID(seq int) string {
	now := time.Now()
	date := now.Format("20060102")
	return fmt.Sprintf("TASK-%s-%03d", date, seq)
}

// ParsePlanMeta extracts the meta section from the bottom of a plan file and returns it as a map
func ParsePlanMeta(planPath string) map[string]string {
	content, err := os.ReadFile(planPath)
	if err != nil {
		return nil
	}

	strContent := string(content)
	metaStart := strings.LastIndex(strContent, "\n---\n")
	if metaStart == -1 {
		return nil
	}

	block := strings.TrimSpace(strContent[metaStart+5:])
	lines := strings.Split(block, "\n")
	meta := make(map[string]string)

	for _, line := range lines {
		line = strings.TrimSpace(line)
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			meta[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	}
	return meta
}

// ParsePlanProgress extracts the number of completed and total checkbox items under the "## Execution Log" section
func ParsePlanProgress(planPath string) (completed int, total int) {
	content, err := os.ReadFile(planPath)
	if err != nil {
		return 0, 0
	}

	strContent := string(content)
	lines := strings.Split(strContent, "\n")
	
	inExecutionLog := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		
		// Check if we entered the Execution Log section
		if strings.HasPrefix(trimmed, "## Execution Log") {
			inExecutionLog = true
			continue
		}
		
		// Exit the section if we encounter another header
		if inExecutionLog && strings.HasPrefix(trimmed, "## ") {
			break
		}
		
		if inExecutionLog {
			// Count "- [ ]" and "- [x]" or "- [X]"
			if strings.HasPrefix(trimmed, "- [") && len(trimmed) >= 5 {
				checkChar := trimmed[3:4] // The character inside []
				if trimmed[4] == ']' {
					total++
					if checkChar == "x" || checkChar == "X" {
						completed++
					}
				}
			}
		}
	}
	
	return completed, total
}

var statusLineRegex = regexp.MustCompile(`(?m)^(\s*status:\s*).*$`)

// UpdatePlanMetaStatus updates the status field in the plan file's meta section.
// Used when task status changes so plan meta stays in sync.
func UpdatePlanMetaStatus(planPath string, metaStatus string) error {
	return UpdatePlanMetaField(planPath, "status", metaStatus)
}

// UpdatePlanMetaField updates a specific field in the plan file's meta section.
// Used when task fields like status or phase change so plan meta stays in sync.
func UpdatePlanMetaField(planPath string, fieldName string, value string) error {
	if planPath == "" || fieldName == "" || value == "" {
		return nil
	}
	content, err := os.ReadFile(planPath)
	if err != nil {
		return err
	}
	strContent := string(content)
	metaStart := strings.LastIndex(strContent, "\n---\n")
	if metaStart == -1 {
		return nil
	}
	beforeMeta := strContent[:metaStart+5]
	metaBlock := strContent[metaStart+5:]

	// Build regex for the specific field
	fieldRegex := regexp.MustCompile(`(?m)^(\s*` + regexp.QuoteMeta(fieldName) + `:\s*).*$`)
	if !fieldRegex.MatchString(metaBlock) {
		return nil
	}
	newMetaBlock := fieldRegex.ReplaceAllString(metaBlock, "${1}"+value)
	return os.WriteFile(planPath, []byte(beforeMeta+newMetaBlock), 0644)
}

// phaseSectionMarkers maps phase name to the ### header in Execution Log
var phaseSectionMarkers = map[string]string{
	"plan": "### Plan 阶段",
	"code": "### Code 阶段",
	"test": "### Test 阶段",
	"done": "### Done 阶段",
}

// IsPhaseCompleted reports whether the given phase's section in the plan has all checkboxes checked.
// Used to avoid triggering the next phase before the current one is done.
func IsPhaseCompleted(planPath, phase string) bool {
	if planPath == "" || phase == "" {
		return false
	}
	marker, ok := phaseSectionMarkers[phase]
	if !ok {
		return false
	}
	content, err := os.ReadFile(planPath)
	if err != nil {
		return false
	}
	lines := strings.Split(string(content), "\n")
	inSection := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, marker) {
			inSection = true
			continue
		}
		if inSection {
			if strings.HasPrefix(trimmed, "### ") || strings.HasPrefix(trimmed, "## ") {
				break
			}
			if strings.HasPrefix(trimmed, "- [ ]") {
				return false
			}
		}
	}
	return inSection
}

// MarkPhaseSectionComplete marks all checklist items in the given phase section as checked,
// so that IsPhaseCompleted(planPath, phase) becomes true and the watcher can trigger the next phase.
func MarkPhaseSectionComplete(planPath, phase string) error {
	if planPath == "" || phase == "" {
		return nil
	}
	marker, ok := phaseSectionMarkers[phase]
	if !ok {
		return nil
	}
	content, err := os.ReadFile(planPath)
	if err != nil {
		return err
	}
	lines := strings.Split(string(content), "\n")
	inSection := false
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, marker) {
			inSection = true
			continue
		}
		if inSection {
			if strings.HasPrefix(trimmed, "### ") || strings.HasPrefix(trimmed, "## ") {
				break
			}
			// Replace - [ ] with - [x] in this line (preserve leading whitespace)
			if strings.Contains(line, "- [ ]") {
				lines[i] = strings.ReplaceAll(line, "- [ ]", "- [x]")
			}
		}
	}
	return os.WriteFile(planPath, []byte(strings.Join(lines, "\n")), 0644)
}
